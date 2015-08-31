require 'minitest/autorun'
require 'rack/show_status'
require 'rack/lint'
require 'rack/mock'
require 'rack/utils'

describe Rack::ShowStatus do
  def show_status(app)
    Rack::Lint.new Rack::ShowStatus.new(app)
  end

  it "provide a default status message" do
    req = Rack::MockRequest.new(
      show_status(lambda{|env|
        [404, {"content-type" => "text/plain", "content-length" => "0"}, []]
    }))

    res = req.get("/", :lint => true)
    res.must_be :not_found?
    res.wont_be_empty

    res["content-type"].must_equal "text/html"
    assert_match(res, /404/)
    assert_match(res, /Not Found/)
  end

  it "let the app provide additional information" do
    req = Rack::MockRequest.new(
      show_status(
        lambda{|env|
          env["rack.showstatus.detail"] = "gone too meta."
          [404, {"content-type" => "text/plain", "content-length" => "0"}, []]
    }))

    res = req.get("/", :lint => true)
    res.must_be :not_found?
    res.wont_be_empty

    res["content-type"].must_equal "text/html"
    assert_match(res, /404/)
    assert_match(res, /Not Found/)
    assert_match(res, /too meta/)
  end

  it "escape error" do
    detail = "<script>alert('hi \"')</script>"
    req = Rack::MockRequest.new(
      show_status(
        lambda{|env|
          env["rack.showstatus.detail"] = detail
          [500, {"content-type" => "text/plain", "content-length" => "0"}, []]
    }))

    res = req.get("/", :lint => true)
    res.wont_be_empty

    res["content-type"].must_equal "text/html"
    assert_match(res, /500/)
    res.wont_include detail
    res.body.must_include Rack::Utils.escape_html(detail)
  end

  it "not replace existing messages" do
    req = Rack::MockRequest.new(
      show_status(
        lambda{|env|
          [404, {"content-type" => "text/plain", "content-length" => "4"}, ["foo!"]]
    }))

    res = req.get("/", :lint => true)
    res.must_be :not_found?

    res.body.must_equal "foo!"
  end

  it "pass on original headers" do
    headers = {"WWW-Authenticate" => "Basic blah"}

    req = Rack::MockRequest.new(
      show_status(lambda{|env| [401, headers, []] }))
    res = req.get("/", :lint => true)

    res["WWW-Authenticate"].must_equal "Basic blah"
  end

  it "replace existing messages if there is detail" do
    req = Rack::MockRequest.new(
      show_status(
        lambda{|env|
          env["rack.showstatus.detail"] = "gone too meta."
          [404, {"content-type" => "text/plain", "content-length" => "4"}, ["foo!"]]
    }))

    res = req.get("/", :lint => true)
    res.must_be :not_found?
    res.wont_be_empty

    res["content-type"].must_equal "text/html"
    res["content-length"].wont_equal "4"
    assert_match(res, /404/)
    assert_match(res, /too meta/)
    res.body.wont_match(/foo/)
  end
end
