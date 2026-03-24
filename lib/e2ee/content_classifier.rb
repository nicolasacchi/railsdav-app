module E2ee
  # Fellegi-Sunter-style probabilistic content classifier for CardDAV payloads.
  # Each feature contributes a log2 weight. Total score maps to probability via sigmoid.
  # Replaces brittle magic-byte detection with multi-feature scoring.
  class ContentClassifier
    BOOTSTRAP_UID = "system-bootstrap@e2e-carddav".freeze

    # Feature weights [agree, disagree]
    WEIGHTS = {
      magic_bytes:          [  8.0, -8.0 ],
      entropy:              [  4.0, -4.0 ],
      ascii_ratio:          [  3.0, -3.0 ],
      vcard_tokens:         [  5.0, -2.0 ],
      e2ee_markers:         [  6.0, -0.5 ],
      bootstrap_uid:        [ 10.0,  0.0 ],
      bootstrap_categories: [  3.0,  0.0 ],
      line_structure:       [  2.0, -2.0 ],
      null_bytes:           [  0.0, -6.0 ],
    }.freeze

    def classify(data)
      return empty_result if data.nil? || data.empty?

      bytes = data.b
      features = extract_features(bytes)
      score, breakdown = compute_score(features)
      classification = determine_classification(score, features)
      probability = sigmoid(score)

      {
        classification: classification,
        score: score.round(2),
        probability: probability.round(6),
        breakdown: breakdown,
        features: features
      }
    end

    def encrypted?(data)
      result = classify(data)
      [:encrypted_blob, :encrypted_vcard].include?(result[:classification])
    end

    def bootstrap?(data)
      classify(data)[:classification] == :bootstrap_vcard
    end

    def plaintext_vcard?(data)
      classify(data)[:classification] == :plaintext_vcard
    end

    private

    def extract_features(bytes)
      {
        magic_bytes:        bytes.start_with?("BEGIN:VCARD".b),
        entropy:            shannon_entropy(bytes),
        ascii_ratio:        ascii_printable_ratio(bytes),
        has_vcard_tokens:   has_vcard_tokens?(bytes),
        has_e2ee_markers:   has_e2ee_markers?(bytes),
        has_bootstrap_uid:  bytes.include?(BOOTSTRAP_UID.b),
        has_bootstrap_cats: bytes.include?("CATEGORIES:SYSTEM,BOOTSTRAP".b) ||
                            bytes.include?("CATEGORIES:SYSTEM\\,BOOTSTRAP".b),
        has_line_structure: has_line_structure?(bytes),
        has_null_bytes:     bytes.include?("\x00".b),
      }
    end

    def compute_score(features)
      score = 0.0
      breakdown = {}

      score += (w = weight(:magic_bytes, features[:magic_bytes]));                breakdown[:magic_bytes] = w
      score += (w = weight(:entropy, features[:entropy] < 6.0));                  breakdown[:entropy] = w
      score += (w = weight(:ascii_ratio, features[:ascii_ratio] > 0.85));         breakdown[:ascii_ratio] = w
      score += (w = weight(:vcard_tokens, features[:has_vcard_tokens]));           breakdown[:vcard_tokens] = w
      score += (w = weight(:e2ee_markers, features[:has_e2ee_markers]));           breakdown[:e2ee_markers] = w
      score += (w = weight(:bootstrap_uid, features[:has_bootstrap_uid]));         breakdown[:bootstrap_uid] = w
      score += (w = weight(:bootstrap_categories, features[:has_bootstrap_cats])); breakdown[:bootstrap_categories] = w
      score += (w = weight(:line_structure, features[:has_line_structure]));        breakdown[:line_structure] = w
      score += (w = weight(:null_bytes, !features[:has_null_bytes]));              breakdown[:null_bytes] = w

      [score, breakdown]
    end

    def determine_classification(score, features)
      if features[:magic_bytes]
        if features[:has_bootstrap_uid]
          :bootstrap_vcard
        elsif features[:has_e2ee_markers]
          :encrypted_vcard
        elsif score >= 8.0
          :plaintext_vcard
        else
          :unknown
        end
      else
        score <= -5.0 ? :encrypted_blob : :unknown
      end
    end

    def weight(feature, condition)
      condition ? WEIGHTS[feature][0] : WEIGHTS[feature][1]
    end

    def shannon_entropy(bytes)
      return 0.0 if bytes.empty?
      freq = Hash.new(0)
      bytes.each_byte { |b| freq[b] += 1 }
      len = bytes.length.to_f
      -freq.values.sum { |c| p = c / len; p * Math.log2(p) }
    end

    def ascii_printable_ratio(bytes)
      return 0.0 if bytes.empty?
      printable = bytes.count("\x20-\x7E\r\n\t")
      printable.to_f / bytes.length
    end

    def has_vcard_tokens?(bytes)
      bytes.include?("VERSION:".b) && bytes.include?("END:VCARD".b)
    end

    def has_e2ee_markers?(bytes)
      bytes.include?("X-E2EE-ALGORITHM".b)
    end

    def has_line_structure?(bytes)
      bytes.include?("\r\n".b) || (bytes.count("\n".b) > 3 && bytes.include?(":".b))
    end

    def sigmoid(score)
      1.0 / (1.0 + 2**(-score))
    end

    def empty_result
      { classification: :unknown, score: 0.0, probability: 0.5, breakdown: {}, features: {} }
    end
  end
end
