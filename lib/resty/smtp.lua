local new_tab = require "table.new"
local setmetatable = setmetatable
local tcp = ngx.socket.tcp
local encode_base64 = ngx.encode_base64
local type = type
local concat = table.concat
local sub = string.sub

local _M = new_tab(0,4)
_M._VERSION = '0.2.0'
local mt = { __index = _M }

function _M.new(self)
    local sock,err = tcp()
    if not sock then return nil, err end

    return setmetatable({ sock = sock }, mt)
end

function _M.set_timeout(self, timeout)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end
    return sock:settimeout(timeout)
end

function _M.connect(self, opts)
    local sock = self.sock
    if not sock then
        return nil, "not initialized"
    end
    local host = opts.host or '127.0.0.1'
    local port = opts.port or 25
    local ok,err = sock:connect(host, port)
    if not ok then
        return nil, 'failed to connect: '.. err
    end
    local ssl_verify = opts.ssl_verify
    local ssl = opts.ssl or ssl_verify
    if ssl then
        local ok, err = sock:sslhandshake(nil, host, ssl_verify)
        if not ok then return nil, 'ssl handshake fail: '.. err end
    end
    return 1
end

function _M.close(self)
    local sock = self.sock
    if not sock then return nil, "not initialized" end

    return sock:close()
end

function _M.receive(self)
    local sock = self.sock
    local line, err = sock:receive()
    if not line then return nil, 'receive err: '.. err end

    local is_multi = sub(line, 4, 4) == '-'
    local o = { line }
    if not is_multi then return o end

    local i = 2
    while is_multi do
        line = sock:receive()
        is_multi = sub(line, 4, 4) == '-'
        o[i] = line
        i = i + 1
    end
    return o
end

function _M.send(self, mail)
    local sock = self.sock
    if not sock then return nil, "not initialized" end
    
    mail = mail or {}
    mail.domain = mail.domain or 'localhost'

    local cmd = {
        {'EHLO ', mail.domain, '\r\n'}, -- greeting
        {'MAIL FROM: <', mail.from, '>\r\n'}, -- from
    }

    local n = 2
    mail.rcpt = type(mail.to) == 'table' and mail.to or {mail.to}

    for i=1,#mail.rcpt do
        n = n + 1
        cmd[n] = {'RCPT TO: <', mail.rcpt[i], '>\r\n'}
    end

    local data = {
        'DATA\r\n', 
        {
            'Subject: ', mail.subject, '\r\n', 
            mail.headers or '\r\n',
            mail.body,
            '\r\n.\r\n', -- end
        }, -- data
        'QUIT\r\n'
    }

    for i=1,#data do
        n = n + 1
        cmd[n] = data[i]
    end

    sock:send(cmd) -- send command

    n = n + 1 -- for initial connnection
    local m = new_tab(n, 0)
    for i=1,n do
        m[i] = _M.receive(self)
    end
    sock:close()
    return m
end

return _M
