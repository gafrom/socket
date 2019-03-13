require 'socket'
require 'forwardable'

socket = Socket.new :INET, :STREAM
addr = Socket.sockaddr_in(3000, '0.0.0.0')
socket.bind(addr)

socket.listen(0) # to start listening, so we could use #accept method

rs = [socket]
ws = []
messages = Hash.new { |hsh, key| hsh[key] = Message.new }
max_len = 2000

def accept_connection(socket, rs)
  # Here we accept in a non_blocking fashion and it is wrong people may say,
  # because the socket came from `IO.select`.
  # Yes, indeed, the socket came from IO.select, but for some reason it may not be ready
  # to connect, in that case we just skip over it.
  client_socket, client_addr = socket.accept_nonblock
  rs << client_socket
rescue IO::EAGAINWaitReadable
  nil
end

class Message < String
  extend Forwardable

  END_TOKEN = 'END'

  attr_accessor :body, :bytes_sent
  def_delegator :@body, :<<

  def initialize
    @body = ''
    @bytes_sent = 0
  end

  def received?
    @body.rstrip.end_with? END_TOKEN
  end

  def sent?
    @bytes_sent == @body.size
  end

  def remaining
    @body[@bytes_sent..-1]
  end
end

begin
  while true
    reads, writes = IO.select(rs, ws)
    reads.each { |s| rs.delete s }
    writes.each { |s| ws.delete s }

    reads.each do |s|
      next accept_connection(s, rs) if s == socket

      msg_read = s.read_nonblock(max_len)
      message = messages[s]
      message << msg_read

      if message.received? # we have read it all, now we can write
        ws << s
      else # we have not read it through, so let's try reading later again
        rs << s
      end
    end

    writes.each do |s|
      # just echoing client's message
      message = messages[s]
      written_bytes = s.write_nonblock(message.remaining)
      message.bytes_sent += written_bytes

      if message.sent?
        s.close # throw away the connection
      else
        ws << s
      end
    end

    rs << socket
  end
ensure
  socket.close
end
