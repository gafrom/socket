require 'socket'

socket = Socket.new :INET, :STREAM
addr = Socket.sockaddr_in(3000, '0.0.0.0')
socket.bind(addr)

socket.listen(0) # to start listening, so we could use #accept method

rs = [socket]
ws = []
messages = {}.tap { |hsh| hsh.default = '' }
max_len = 2000
END_TOKEN = 'END'

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

begin
  while true
    reads, writes = IO.select(rs, ws)
    reads.each { |s| rs.delete s }
    writes.each { |s| ws.delete s }

    reads.each do |s|
      next accept_connection(s, rs) if s == socket

      msg = s.read_nonblock(max_len)
      messages[s] += msg

      puts messages[s]

      if messages[s].rstrip.end_with? END_TOKEN # we have read it all, now we can write
        ws << s
      else # we have not read it through, so let's try reading later again
        rs << s
      end
    end

    writes.each do |s|
      # just echoing client's message
      written_bytes = s.write_nonblock(messages[s])
      if written_bytes == messages[s].size
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
