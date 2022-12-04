#!/usr/bin/env lua
local Interpreter = require('luaturtle.interp')
local jsval = require('luaturtle.jsval')
local compat = require('luaturtle.compat')

local PROMPT = '>>> '

function repl()
   local i = Interpreter:new()
   local silent = (arg[1] ~= nil)
   local prompt = function() if not silent then io.stdout:write(PROMPT) end end

   prompt()
   for line in io.lines(compat.unpack(arg)) do
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

function readAll(filenames)
   -- Execute all files in the same execution context
   local i = Interpreter:new()
   for _,filename in ipairs(filenames) do
      local source = io.input(filename):read('*a') -- leading * needed for Lua < 5.3
      status, r = i:interpret(source)
      if not status then
         if jsval.isJsVal(r) then
            local msg = i.env:prettyPrint(r)
            error(msg)
         else
            error(r)
         end
      end
   end
end

if arg[1] ~= nil then
   readAll(arg)
else
   repl()
end
