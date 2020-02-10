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
   -- Create repl
   local makeRepl = jsval.invokePrivate(
      i.env, i.compileFromSource, 'GetV', jsval.newString('make_repl')
   )
   i.replFunc = i.env:interpretFunction( makeRepl, jsval.Null, {} )
   return i
end

-- Compile a source string to bytecode and then execute it
function Interpreter:interpret(source)
   -- compile source to bytecode
   local bc = self.env:interpretFunction(
      self.compileFromSource, jsval.Null, { jsval.newString( source ) }
   )
   -- XXX handle exceptions thrown during compilation (syntax errors)
   -- Create a new module from the bytecode
   return self:createModuleAndExecute( bc )
end

-- Execute a source string in a REPL.
function Interpreter:repl(source)
   -- compile source to bytecode
   local bc = self.env:interpretFunction(
      self.replFunc, jsval.Null, { jsval.newString( source ) }
   )
   -- XXX handle exceptions thrown during compilation (syntax errors)
   -- Create a new module from the bytecode
   return self:createModuleAndExecute( bc )
end

function Interpreter:createModuleAndExecute(bc)
   local buf = {}
   self.env:arrayEach(bc, function(val)
     table.insert(buf, string.char(jsval.toLua(val)))
   end)
   local nm = Module:newFromBytes( table.concat(buf) )
   -- Execute the new module
   return self.env:interpret( nm, 0, self.frame )
end

return Interpreter
