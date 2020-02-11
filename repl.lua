#!/usr/bin/env lua
local Interpreter = require('luaturtle.interp')
local jsval = require('luaturtle.jsval')

local PROMPT = '>>> '

function repl()
   i = Interpreter:new()
   local silent = (arg[1] ~= nil)
   local prompt = function() if not silent then io.stdout:write(PROMPT) end end

   prompt()
   for line in io.lines(table.unpack(arg)) do
      local status, result = i:repl(line)
      if status then
         if not silent then print(i.env:prettyPrint(result)) end
      elseif jsval.isJsVal(result) then
         local msg = i.env:prettyPrint(result)
         if silent then error(msg) else print('*', msg) end
      else
         error(result)
      end
      prompt()
   end
end

repl()
