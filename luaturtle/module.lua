-- A compilation unit (which can be as small as a single function)
local startup = require('luaturtle.startup')
local jsval = require('luaturtle.jsval')
local ifunc = require('luaturtle.ifunc')
local compat = require('luaturtle.compat')

-- Helper class to read the bytecode format
local ModuleReader = {}
ModuleReader.__index = ModuleReader
function ModuleReader:new(buf)
   return setmetatable({ buf = buf, pos = 1 }, self)
end

function ModuleReader:decodeUint()
   local val = string.byte(self.buf, self.pos)
   self.pos = self.pos + 1
   if val < 128 then
      return val
   end
   return (val - 128) + ( 128 * self:decodeUint() )
end

function ModuleReader:decodeUtf16Str()
   local len = self:decodeUint()
   local s = {}
   for i = 1, len do
      local c = self:decodeUint()
      local msb, lsb = compat.splitBytes(c)
      table.insert(s, string.char(msb, lsb))
   end
   return table.concat(s)
end

function ModuleReader:decodeUtf8Str()
   return jsval.convertUtf16ToUtf8(self:decodeUtf16Str())
end

function ModuleReader:decodeJsStr()
   return jsval.newStringFromUtf16(self:decodeUtf16Str())
end

-- A compilation unit
local Module = {}
Module.__index = Module

function Module:new(o)
   o = o or { functions = {}, literals = {} }
   setmetatable(o, self)
   o.type = 'Module'
   return o
end

function Module:newStartupModule()
   return self:new{functions = startup.functions, literals = startup.literals}
end

function Module:newFromBytes(buf)
   local reader = ModuleReader:new(buf)
   -- Parse the functions
   local num_funcs = reader:decodeUint()
   local functions = {}
   local func_id = 0
   while func_id < num_funcs do
      local nargs = reader:decodeUint()
      local max_stack = reader:decodeUint()
      local name = reader:decodeJsStr()
      local blen = reader:decodeUint()
      local bytecode = {}
      while #bytecode < blen do
         table.insert(bytecode, reader:decodeUint())
      end
      if #name == 0 then name = jsval.Undefined end
      local func = ifunc.Function:new{
         name = name,
         id = func_id,
         nargs = nargs,
         max_stack = max_stack,
         bytecode = bytecode,
      }
      table.insert(functions, func)
      func_id = func_id + 1
   end
   -- Parse literals
   local num_lits = reader:decodeUint()
   local literals = {}
   local decode = {
      [0] = function() -- Number
         local numStr = reader:decodeJsStr()
         return jsval.invokePrivate(nil, numStr, 'ToNumber')
      end,
      [1] = function() -- String
         return reader:decodeJsStr()
      end,
      [2] = function() -- Boolean tags
         return jsval.True
      end,
      [3] = function() return jsval.False end,
      [4] = function() return jsval.Null end,
      [5] = function() return jsval.Undefined end,
   }
   while #literals < num_lits do
      local ty = reader:decodeUint()
      local val = decode[ty]()
      table.insert(literals, val)
   end
   return self:new{ functions = functions, literals = literals }
end

return Module
