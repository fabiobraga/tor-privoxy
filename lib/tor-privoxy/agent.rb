require 'net/telnet'
require 'mechanize'

module TorPrivoxy
  class Agent
    def initialize host, pass, control, &callback
      @proxy = Switcher.new host, pass, control
      @mechanize = Mechanize.new
      @mechanize.set_proxy(@proxy.host, @proxy.port)
      @circuit_timeout = 10
      @callback = callback
      @callback.call self
    end

    def method_missing method, *args, &block
      max = 3

      ok = false
      while max >= 0 and not ok
        begin
          max = max - 1
          @mechanize.send method, *args, &block
          ok = true
        rescue Mechanize::ResponseCodeError # 403 etc
          switch_circuit
          retry
        end
      end
    end

    def switch_circuit
      localhost = Net::Telnet::new('Host' => @proxy.host, 'Port' => @proxy.control_port,
                                 'Timeout' => @circuit_timeout, 'Prompt' => /250 OK\n/)
      localhost.cmd("AUTHENTICATE \"#{@proxy.pass}\"") { |c| throw "cannot authenticate to Tor!" if c != "250 OK\n" }
      localhost.cmd('signal NEWNYM') { |c| throw "cannot switch Tor to new route!" if c != "250 OK\n" }
      localhost.close

      @proxy.next
      @mechanize = Mechanize.new
      @mechanize.set_proxy(@proxy.host, @proxy.port)

      @callback.call self
    end

    def ip
      @mechanize.get('http://ipinfo.io/ip').body
    rescue Exception => ex
      puts "error getting ip: #{ex.to_s}"
      return ""
    end
  end
end
