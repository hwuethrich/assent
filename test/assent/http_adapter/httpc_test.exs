defmodule Assent.HTTPAdapter.HttpcTest do
  use ExUnit.Case
  doctest Assent.HTTPAdapter.Httpc

  alias ExUnit.{CaptureIO, CaptureLog}
  alias Assent.HTTPAdapter.{Httpc, HTTPResponse}

  describe "request/4" do
    test "handles SSL" do
      TestServer.start(scheme: :https)
      TestServer.add("/", via: :get)

      httpc_opts = Httpc.httpc_opts_with_cacerts(TestServer.url(), TestServer.x509_suite().cacerts)

      assert {:ok, %HTTPResponse{status: 200, body: "HTTP/1.1"}} = Httpc.request(:get, TestServer.url(), nil, [], httpc_opts)
    end

    test "handles SSL with bad certificate" do
      TestServer.start(scheme: :https)
      TestServer.add("/", via: :get)

      bad_host_url = TestServer.url(host: "bad-host.localhost")
      httpc_opts = Httpc.httpc_opts_with_cacerts(bad_host_url, TestServer.x509_suite().cacerts)

      assert {:error, {:failed_connect, error}} = Httpc.request(:get, bad_host_url, nil, [], httpc_opts)
      assert {:tls_alert, {:handshake_failure, _error}} = fetch_inet_error(error)

      # For OTP 24 "Authenticity is not established by certificate path validation" warning
      CaptureLog.capture_log(fn ->
        assert CaptureIO.capture_io(:stderr, fn ->
          assert {:ok, %HTTPResponse{status: 200}} = Httpc.request(:get, TestServer.url(), nil, [], ssl: [])
        end) =~ "This request will NOT be verified for valid SSL certificate"
      end)
    end

    test "handles unreachable host" do
      TestServer.start()
      url = TestServer.url()
      TestServer.stop()

      assert {:error, {:failed_connect, error}} = Httpc.request(:get, url, nil, [])
      assert fetch_inet_error(error) == :econnrefused
    end

    test "handles query in URL" do
      TestServer.add("/get", via: :get, to: fn conn ->
        assert conn.query_string == "a=1"

        Plug.Conn.send_resp(conn, 200, "")
      end)

      assert {:ok, %HTTPResponse{status: 200}} = Httpc.request(:get, TestServer.url("/get?a=1"), nil, [])
    end

    test "handles POST" do
      TestServer.add("/post", via: :post, to: fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn, [])
        params = URI.decode_query(body)

        assert params["a"] == "1"
        assert params["b"] == "2"
        assert Plug.Conn.get_req_header(conn, "content-type") == ["application/x-www-form-urlencoded"]

        Plug.Conn.send_resp(conn, 200, "")
      end)

      assert {:ok, %HTTPResponse{status: 200}} = Httpc.request(:post, TestServer.url("/post"), "a=1&b=2", [{"content-type", "application/x-www-form-urlencoded"}])
    end
  end

  defp fetch_inet_error([_, {:inet, [:inet], error}]), do: error
end
