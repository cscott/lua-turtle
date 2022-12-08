-- Simple REPL
local Interpreter = require('luaturtle.interp')
local jsval = require('luaturtle.jsval')

local i = nil
function reset()
   i = Interpreter:new()
end

function repl(line)
   local status, result = i:repl(line)
   if status then
      if not silent then print(i.env:prettyPrint(result)) end
   elseif jsval.isJsVal(result) then
      local msg = i.env:prettyPrint(result)
      if silent then error(msg) else print('*', msg) end
   else
      error(result)
   end
end

-- This version takes a Scribunto 'frame' argument.
function eval(frame)
   local line = frame.args[1] or '"Hello, world"'
   local status, result = i:repl(line)
   if status then
      if jsval.Type(result) == 'String' then
         -- If the JS returns a string, don't try to "pretty print" it,
         -- just return it directly
         return tostring(result)
      end
      -- otherwise try to pretty print the result to make it
      -- human-friendly
      return i.env:prettyPrint(result)
   elseif jsval.isJsVal(result) then
      local msg = i.env:prettyPrint(result)
      return '* ' .. msg
   else
      return result
   end
end

reset()

return {
   reset = reset,
   repl = repl,
   eval = eval,
}
