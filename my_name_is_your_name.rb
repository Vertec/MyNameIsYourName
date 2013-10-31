#!/usr/bin/env ruby
# encoding: UTF-8

require 'rubydns'
require 'trollop'
require 'eventmachine'

module MyNameIsYourName

opts = Trollop::options do
	version "My Name Is Your Name 1.0. © 2013 Vertec AG"
  banner <<-EOS
My Name Is Your Name: DNS Server that tries to resolve WINS names.

Usage:
       ruby my_name_is_your_name.rb [options]

where [options] are:
EOS
	opt :upstream, "Use an upstream server to serve non-WINS requests. Using “system” will use the system’s default DNS servers.", default: ['system'], short: 'u'
	opt :"no-upstream", "Don’t use an upstream server. Non-WINS requests will not be answered.", short: 'n', default: false
	opt :tlds, "The TLD(s) to listen for.", short: 't', default: ['wins', 'windows-computer', 'local']
	opt :"all", "Try to answer all requests for a valid WINS name, without having to use a TLD.", short: 'a', default: false
	opt :"dot", "Allow WINS names to contain dots (before the TLD). Enabling this costs performance, especially when used with --all.", short: 'd', default: false
end

# Use upstream DNS for name resolution.
upstream = nil
unless opts[:"no-upstream"]
	resolvers = []
	opts[:upstream].each do |resolver|
		if resolver === 'system' then
			require 'rubydns/system'
			resolvers = resolvers.concat(RubyDNS::System::nameservers)
		else
			resolvers.push([:udp, resolver, 53], [:tcp, resolver, 53])
		end
	end
	upstream = RubyDNS::Resolver.new(resolvers)
end
UPSTREAM = upstream

# WINS Name matching expression
CHARACTERS = Regexp.quote('_-' + (opts[:dot] ? '.' : ''))
TLDS = opts[:tlds].map do |tld|
	Regexp.quote("."+tld)
end
PATTERN = Regexp.new('^([a-zA-Z'+CHARACTERS+']+?)('+TLDS.join('|')+')'+(opts[:all] ? '?' : '')+'$')


def self.run
	# Start the RubyDNS server
	RubyDNS::run_server() do

		
		match(PATTERN, Resolv::DNS::Resource::IN::A) do |transaction, match_data|
			transaction.defer!
			host = match_data[1]
			process = EventMachine::DeferrableChildProcess.open("smbutil lookup "+host)
			process.callback do |data|
				data = data.split(/\s/);
				if data.length == 0 then
					unless UPSTREAM.nil? then
						transaction.passthrough!(UPSTREAM)
					else
						transaction.failure!(:NXDomain)
					end
				else
					transaction.respond!(data.pop)
				end
			end
		end

		unless UPSTREAM.nil? then
			# Default DNS handler
			otherwise do |transaction|
				transaction.passthrough!(UPSTREAM)
			end
		end
	end
	
end

trap("INT") do
	EventMachine.stop
end

run()

end
