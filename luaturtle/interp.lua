local Env = require('luaturtle.env')
local Module = require('luaturtle.module')
local jsval = require('luaturtle.jsval')

local Interpreter = {}
Interpreter.__index = Interpreter

function Interpreter:new()
   local i = {}
   setmetatable(i, self)
   i.env = Env:new()
   i.modul = Module:newStartupModule()
   i.frame = i.env:makeTopLevelFrame( jsval.Null, {} )
   i.compileFromSource = i.env:interpret( i.modul, 0, i.frame )
   -- Create JSON parser
   i.compileJSON = jsval.invokePrivate(
      i.env, i.compileFromSource, 'GetV', jsval.newString('parse_json')
   )
   local JSON = i.env.realm.JSON
   i.env:addNativeFunc(i.env.realm.JSON, 'parse', 2, function(this, args)
      local status, bc = i.env:interpretFunction(
         i.compileJSON, jsval.Null, { (args[1] or jsval.Undefined) }
      )
      if not status then
         error(bc) -- native throw!
      end
      status, result = i:createModuleAndExecute(bc)
      if not status then
         error(bc) -- this should never happen
      end
      return result
   end)
   -- Create repl
   local makeRepl = jsval.invokePrivate(
      i.env, i.compileFromSource, 'GetV', jsval.newString('make_repl')
   )
   local status, replFunc = i.env:interpretFunction( makeRepl, jsval.Null, {} )
   assert(status, replFunc)
   i.replFunc = replFunc
   return i
end

-- Compile a source string to bytecode and then execute it
-- Returns a status, result pair
function Interpreter:interpret(source)
   -- compile source to bytecode
   local status, bc = self.env:interpretFunction(
      self.compileFromSource, jsval.Null, { jsval.newString( source ) }
   )
   if not status then
      return status, bc -- Syntax error during compilation
   end
   -- Create a new module from the bytecode
   return self:createModuleAndExecute( bc )
end

-- Execute a source string in a REPL.
function Interpreter:repl(source)
   -- compile source to bytecode
   local status, bc = self.env:interpretFunction(
      self.replFunc, jsval.Null, { jsval.newString( source ) }
   )
   if not status then
      return status, bc -- Syntax error during compilation
   end
   -- Create a new module from the bytecode
   return self:createModuleAndExecute( bc )
end

function Interpreter:createModuleAndExecute(bc)
   local buf = {}
   self.env:arrayEach(bc, function(val)
     table.insert(buf, string.char(jsval.toLua(self.env, val)))
   end)
   local nm = Module:newFromBytes( table.concat(buf) )
   -- Execute the new module
   if true then -- lua 5.1
      return pcall(function()
            return self.env:interpret(nm, 0, self.frame)
      end)
   else
      -- Set up error-handling
      return xpcall(
         self.env.interpret, debug.traceback, self.env, nm, 0, self.frame
      )
   end
end

return Interpreter
