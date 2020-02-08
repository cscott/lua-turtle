-- Bytecode interpreter
local ops = require('ops')
local jsval = require('jsval')

local interp = {}

local State = {}
State.__index = State

function State:new(parent, frame, modul, func)
   local o = {
      parent = parent,
      frame = frame,
      stack = {},
      pc = 1, -- lua indexing is 1-based
      -- from bytecode file
      modul = modul,
      func = func
   }
   setmetatable(o, self)
   return o
end

function State:push(v)
   table.insert(self.stack, v)
end

function State:pop()
   return table.remove(self.stack)
end

function State:getnext()
   local n = self.func.bytecode[self.pc]
   self.pc = self.pc + 1
   return n
end

-- JavaScript execution environment
-- Consists of a realm, well-known symbols, etc.
local Env = {}

function Env:new()
   local env = {
      realm = {},
      symbols = {}
   }
   setmetatable(o, self)

   o.Object = jsval.Object() -- parent of all objects
   o.Object.type = 'object'

   o.Array = jsval.Object(o.Object)
   o.Array.type = 'array'
   o.Array[jsval.String('length')] = 0

   return o
end



local function nyi(which)
   error("Not yet implemented: " + which)
end


local one_step = {
   [ops.PUSH_FRAME] = function(env, state)
      state:push(state.frame)
   end,
   [ops.PUSH_LITERAL] = function(env, state)
      state:push(state.modul.literals[1+state:getnext()])
   end,
   [ops.NEW_OBJECT] = function(env, state)
      state:push(jsval.Object(env.Object))
   end,
   [ops.NEW_ARRAY] = function(env, state)
      state:push(jsval.Array())
   end,
   [ops.NEW_FUNCTION] = nyi('NEW_FUNCTION'),
   [ops.GET_SLOT_DIRECT] = function(env, state)
      local obj = state:pop()
      local name = state.modul.literals[1+state:getnext()]
      state:push(obj[name])
   end,
   [ops.GET_SLOT_DIRECT_CHECK] = function(env, state)
      local obj = state:pop()
      local name = state.modul.literals[1+state:getnext()]
      local result = obj[name]
      if result.type !== 'object' then
         -- warn about unimplemented (probably library) functions
         io.write('Failing lookup of method ', name.to_str(), "\n")
      end
      state:push(result)
   end,
   [ops.SET_SLOT_DIRECT] = function(env, state)
      local nval = state:pop()
      local name = state.modul.literals[1+state:getnext()]
      local obj = state:pop()
      obj[name] = nval
   end,
   [ops.SET_SLOT_INDIRECT] = function(env, state)
      local nval = state:pop()
      local name = state:pop()
      local obj = state:pop()
      obj[name] = nval
   end,
   [ops.INVOKE] = function(env, state)
      return env:invoke(state, state:getnext())
   end,
   [ops.RETURN] = function(env, state)
      local retval = state:pop()
      -- go up to the parent state
      state = state.parent
      state:push(retval)
      return state -- continue in parent state
   end,
   -- branches
   [ops.JMP] = function(env, state)
      state.pc = state:getnext() + 1 -- convert to 1-based indexing
   end,
   [ops.JMP_UNLESS] = function(env, state)
      local arg1 = state:getnext()
      local cond = state:pop()
      if not env:toBoolean(cond) then
         state.pc = arg1 + 1 -- convert to 1-based indexing
      end
   end,
   -- stack manipulation
   [ops.POP] = function(env, state)
      state:pop()
   end,
   [ops.DUP] = function(env, state)
      local top = state:pop()
      state:push(top)
      state:push(top)
   end,
   [ops.DUP2] = function(env, state)
      local top = state:pop()
      local nxt = state:pop()
      state:push(nxt)
      state:push(top)
      state:push(nxt)
      state:push(top)
   end,
   [ops.OVER] = function(env, state)
      local top = state:pop()
      local nxt = state:pop()
      state:push(top)
      state:push(nxt)
      state:push(top)
   end,
   [ops.OVER2] = function(env, state)
      local top = state:pop()
      local nx1 = state:pop()
      local nx2 = state:pop()
      state:push(top)
      state:push(nx2)
      state:push(nx1)
      state:push(top)
   end,
   [ops.SWAP] = function(env, state)
      local top = state:pop()
      local nxt = state:pop()
      state:push(top)
      state:push(nxt)
   end,
   -- unary operators
   [ops.UN_NOT] = nyi('UN_NOT'),
   [ops.UN_MINUS] = nyi('UN_MINUS'),
   [ops.UN_TYPEOF] = nyi('UN_TYPEOF'),
   [ops.BI_EQ] = nyi('BI_EQ'),
   [ops.BI_GT] = nyi('BI_GT'),
   [ops.BI_GTE] = nyi('BI_GTE'),
   [ops.BI_ADD] = nyi('BI_ADD'),
   [ops.BI_SUB] = nyi('BI_SUB'),
   [ops.BI_MUL] = nyi('BI_MUL'),
   [ops.BI_DIV] = nyi('BI_DIV')
}

function Env:interpet_one(state)
   local op = state:getnext()
   local nstate = one_step[op](self, state) or state
   return nstate
end

function Env:interpret(modul, func_id, frame)
   local frame2 = frame
   if frame2 == nil then
      frame2 = self:make_top_level_frame(jsval.Null, {})
   end
   local func = modul.functions[func_id]
   local top = State:new(nil, frame2, modul, func)
   local state = State:new(top, frame2, modul, func)
   while state.parent != nil do -- wait for state == top
      state = self:interpret_one(state)
   end
   return state:pop()
end

return interp
