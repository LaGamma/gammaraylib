
from std.collections import List
from std.ffi import OwnedDLHandle, c_int, c_char
from std.sys import is_defined

comptime WS_BUF_SIZE = 16384

comptime WS_STATE_CLOSED: Int     = 0
comptime WS_STATE_CONNECTING: Int = 1
comptime WS_STATE_OPEN: Int       = 2
comptime WS_STATE_ERROR: Int      = 3


struct WebSocketClient(Movable):
    var lib: OwnedDLHandle
    var rx_buf: List[UInt8]

    def __init__(out self) raises:
        comptime if is_defined["WASM"]():
            self.lib = OwnedDLHandle()
        else:
            self.lib = OwnedDLHandle("build/native/libgrl_ws.so")
        self.rx_buf = List[UInt8](length=WS_BUF_SIZE, fill=0)

    def connect(self, mut url: String) raises -> Bool:
        var fn_connect = self.lib.get_function[c_int]("grl_ws_connect")
        var null_term = url + "\x00"
        var span = null_term.as_c_string_span()
        var ptr = Pointer[c_char, MutAnyOrigin](unsafe_from_address=Int(span.ptr()))
        var rc = fn_connect(ptr)
        if null_term.byte_length() == 0:
            return False
        return rc == 0

    def state(self) raises -> Int:
        var fn_state = self.lib.get_function[c_int]("grl_ws_state")
        return Int(fn_state())

    def is_open(self) raises -> Bool:
        return self.state() == WS_STATE_OPEN

    def send(self, mut message: String) raises -> Bool:
        var fn_send = self.lib.get_function[c_int]("grl_ws_send")
        var byte_len = c_int(message.byte_length())
        var null_term = message + "\x00"
        var span = null_term.as_c_string_span()
        var ptr = Pointer[c_char, MutAnyOrigin](unsafe_from_address=Int(span.ptr()))
        var sent = fn_send(ptr, byte_len)
        if null_term.byte_length() == 0:
            return False
        return sent >= 0

    def poll(mut self) raises -> String:
        var fn_poll = self.lib.get_function[c_int]("grl_ws_poll")
        var ptr = Pointer[c_char, MutAnyOrigin](unsafe_from_address=Int(self.rx_buf.unsafe_ptr()))
        var n = Int(fn_poll(ptr, c_int(WS_BUF_SIZE)))
        if n < 0:
            self.close()
            return ""
        if n == 0:
            return ""
        self.rx_buf[n] = 0
        return String(unsafe_from_utf8_ptr=ptr)

    def close(self) raises:
        var fn_close = self.lib.get_function[c_int]("grl_ws_close")
        _ = fn_close()
