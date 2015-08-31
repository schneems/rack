require 'minitest/autorun'
require 'rack/head'
require 'rack/lint'
require 'rack/mock'

describe Rack::Head do

  def test_response(headers = {})
    body = StringIO.new "foo"
    app = lambda do |env|
      [200, {"content-type" => "test/plain", "content-length" => "3"}, body]
    end
    request = Rack::MockRequest.env_for("/", headers)
    response = Rack::Lint.new(Rack::Head.new(app)).call(request)

    return response, body
  end

  it "pass GET, POST, PUT, DELETE, OPTIONS, TRACE requests" do
    %w[GET POST PUT DELETE OPTIONS TRACE].each do |type|
      resp, _ = test_response("request_method" => type)

      resp[0].must_equal 200
      resp[1].must_equal "content-type" => "test/plain", "content-length" => "3"
      resp[2].to_enum.to_a.must_equal ["foo"]
    end
  end

  it "remove body from HEAD requests" do
    resp, _ = test_response("request_method" => "HEAD")

    resp[0].must_equal 200
    resp[1].must_equal "content-type" => "test/plain", "content-length" => "3"
    resp[2].to_enum.to_a.must_equal []
  end

  it "close the body when it is removed" do
    resp, body = test_response("request_method" => "HEAD")
    resp[0].must_equal 200
    resp[1].must_equal "content-type" => "test/plain", "content-length" => "3"
    resp[2].to_enum.to_a.must_equal []
    body.wont_be :closed?
    resp[2].close
    body.must_be :closed?
  end
end
