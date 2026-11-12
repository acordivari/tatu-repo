require "test_helper"

# The classifier must never turn an unusable response into a confident verdict:
# a bogus "person" hides real work, which is worse than leaving it unclassified.
class WorkImageClassifierTest < ActiveSupport::TestCase
  def parse(text)
    WorkImageClassifier.allocate.send(:parse, text)
  end

  test "parses a well-formed verdict" do
    v = parse('{"kind": "person", "confidence": 0.82}')

    assert_equal "person", v.kind
    assert_in_delta 0.82, v.confidence
    assert_not v.work?
  end

  test "tolerates prose around the JSON" do
    assert_equal "tattoo", parse('Here you go: {"kind":"tattoo","confidence":0.9} ').kind
  end

  test "returns nil for an unknown kind rather than guessing" do
    assert_nil parse('{"kind": "flash", "confidence": 0.9}')
    # v5 dropped "work" from the prompt; a reply using it is stale, not a verdict.
    assert_nil parse('{"kind": "work", "confidence": 0.9}')
  end

  test "returns nil for unparseable output" do
    assert_nil parse("I cannot tell what this is")
    assert_nil parse('{"kind": broken')
  end

  test "version is recorded so a prompt change can invalidate past verdicts" do
    assert WorkImageClassifier::VERSION.present?
  end

  test "prompt carries OCR text only when there is some" do
    assert_equal WorkImageClassifier::INSTRUCTIONS, WorkImageClassifier.prompt(nil)
    assert_equal WorkImageClassifier::INSTRUCTIONS, WorkImageClassifier.prompt("  \n ")

    prompt = WorkImageClassifier.prompt("TORONTO\nSUMMER FALL 2026\nBOOKING AVAILABLE")
    assert prompt.start_with?(WorkImageClassifier::INSTRUCTIONS)
    assert_includes prompt, "TORONTO SUMMER FALL 2026 BOOKING AVAILABLE"
  end

  test "prompt truncates long OCR text" do
    prompt = WorkImageClassifier.prompt("word " * 500)
    assert_operator prompt.length, :<, WorkImageClassifier::INSTRUCTIONS.length +
                                       WorkImageClassifier::OCR_CONTEXT.length +
                                       WorkImageClassifier::OCR_MAX_CHARS
  end

  test "tattoo and design both count as work" do
    assert parse('{"kind": "tattoo", "confidence": 0.9}').work?
    assert parse('{"kind": "design", "confidence": 0.9}').work?
    assert_not parse('{"kind": "other", "confidence": 0.9}').work?
  end

  # v8: the making of a tattoo is a verdict of its own, and not portfolio work.
  test "process is a valid verdict that does not count as work" do
    v = parse('{"kind": "process", "confidence": 0.9}')

    assert_equal "process", v.kind
    assert_not v.work?
    assert_includes Post::NOT_WORK_KINDS, "process"
  end

  test "every kind the prompt offers is either shown or hidden, never neither" do
    WorkImageClassifier::KINDS.each do |kind|
      assert_includes WorkImageClassifier::INSTRUCTIONS, %("#{kind}")
      assert Post::WORK_KINDS.include?(kind) ^ Post::NOT_WORK_KINDS.include?(kind),
             "#{kind} must be in exactly one of WORK_KINDS and NOT_WORK_KINDS"
    end
  end

  # v9: the picture is judged first; burned-in text gets a second look that can
  # only add "promo". Stubs #ask, recording which calls carried the OCR text.
  def two_look(first:, second: nil)
    asked = []
    classifier = WorkImageClassifier.allocate
    classifier.define_singleton_method(:ask) do |_bytes, ocr_text, _caption|
      asked << ocr_text
      kind = ocr_text.nil? ? first : second
      kind && WorkImageClassifier::Verdict.new(kind: kind, confidence: 0.9)
    end
    [ classifier, asked ]
  end

  test "the first look never sees burned-in text" do
    classifier, asked = two_look(first: "process")

    assert_equal "process", classifier.classify("jpg", ocr_text: "the finished piece", caption: "Done!").kind
    assert_equal [ nil ], asked
  end

  test "burned-in text cannot turn a process shot into a tattoo" do
    classifier, = two_look(first: "process", second: "tattoo")

    assert_equal "process", classifier.classify("jpg", ocr_text: "the finished piece").kind
  end

  test "burned-in text can turn work into promo, and nothing else" do
    classifier, asked = two_look(first: "tattoo", second: "promo")
    assert_equal "promo", classifier.classify("jpg", ocr_text: "BERLIN 27/10-30/10 BOOKS OPEN").kind
    assert_equal [ nil, "BERLIN 27/10-30/10 BOOKS OPEN" ], asked

    %w[design person process other].each do |second|
      classifier, = two_look(first: "tattoo", second: second)
      assert_equal "tattoo", classifier.classify("jpg", ocr_text: "Worth the wait.").kind, "second look said #{second}"
    end
  end

  test "an image with no burned-in text is judged once" do
    classifier, asked = two_look(first: "tattoo", second: "promo")

    assert_equal "tattoo", classifier.classify("jpg", ocr_text: " \n ").kind
    assert_equal [ nil ], asked
  end

  test "a failed second look is unknown, not a verdict" do
    classifier, = two_look(first: "design", second: nil)

    assert_nil classifier.classify("jpg", ocr_text: "TOUR DATES")
  end

  test "a failed first look is unknown" do
    classifier, asked = two_look(first: nil, second: "promo")

    assert_nil classifier.classify("jpg", ocr_text: "TOUR DATES")
    assert_equal [ nil ], asked
  end

  test "prompt carries the caption as medium context only when present" do
    assert_equal WorkImageClassifier::INSTRUCTIONS, WorkImageClassifier.prompt(nil, "  ")

    prompt = WorkImageClassifier.prompt(nil, "Latest painting I've been working on.\n26x31 inches")
    assert_includes prompt, "Latest painting I've been working on. 26x31 inches"
    assert_includes prompt, "do not make the image \"promo\""
  end
end
