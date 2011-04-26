#!/usr/bin/env rackup
# encoding: utf-8
#\ -E deployment

require 'em-http'
require 'pool'

# Command, starting port, min servers, max servers
POOL = Pool.new("sh -c 'cd /tmp && rackup -p $PORT'", 3001, 1, 2)

Signal.trap("INT") do
	POOL.shutdown
	exit
end

def headers(env)
	env.keys.select {|key| key =~ /^HTTP_/ }.inject({}) do |h, k|
		next h if k == 'HTTP_SERVER'
		next h if k == 'HTTP_VERSION'
		header = k.sub(/^HTTP_/, '').gsub(/_/, '-')
		h.merge!({header => env[k]})
	end
end

def proxy_request(env)
	POOL.next do |port|
		http = EventMachine::HttpRequest.new(
			"http://localhost:#{port}#{env['PATH_INFO']}").
			setup_request(env['REQUEST_METHOD'],
			              :head => headers(env),
			              :query => env['QUERY_STRING'],
			              :body => env['rack.input'].read)

		http.callback {
			POOL.done_with(port)
			env['async.callback'].call([
				http.response_header.status, http.response_header,
				http.response
			])
		}

		http.errback {
			POOL.done_with(port)
			if http.response_header.status == 0
				proxy_request(env) # retry
			else
				env['async.callback'].call([
					http.response_header.status, http.response_header,
					http.response
				])
			end
		}
	end

	[-1, {}, []]
end

run method(:proxy_request)
