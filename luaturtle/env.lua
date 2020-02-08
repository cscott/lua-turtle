-- JavaScript execution environment
-- Consists of a realm, well-known symbols, etc
local ops = require('luaturtle.ops')
local jsval = require('luaturtle.jsval')

-- Bytecode interpreter execution state
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

function State:__tostring()
   local s = ''
   for k,v in pairs(self) do
      s = s .. k .. '=' .. tostring(v) .. ','
   end
   return 'State{' .. s .. '}'
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
-- (Also the bytecode interpreter!)
local Env = {}
Env.__index = Env

function Env:new()
   local env = {
      realm = {},
      symbols = {}
   }
   setmetatable(env, self)

   -- %ObjectPrototype%, the parent of all Objects
   local ObjectPrototype = jsval.newObject(env, jsval.Null)
   env.realm.ObjectPrototype = ObjectPrototype
   jsval.extendObj(ObjectPrototype)
   getmetatable(ObjectPrototype)['[[SetPrototypeOf]]'] =
      getmetatable(ObjectPrototype)['SetImmutablePrototype']

   return env
end

function Env:arrayCreate(luaArray)
   -- XXX this is a hack, we need a proper Array type
   local arr = jsval.newObject(self, self.realm.ObjectPrototype)
   local max = 0
   for i,v in ipairs(luaArray) do
      arr[i-1] = v
      if i > max then max = i end
   end
   arr.length = max
   return arr
end

function Env:makeTopLevelFrame(context, arguments)
   local frame = jsval.newObject(self, jsval.Null) -- Object.create(null)
   -- set up 'this' and 'arguments'
   frame.this = context
   frame.arguments = self:arrayCreate(arguments)

   -- constructors
   return frame
end


local function nyi(which)
   return function()
      error("Not yet implemented: " .. which)
   end
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
      if result.type ~= 'object' then
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
   [ops.BI_ADD] = function(env, state)
      local right = state:pop()
      local left = state:pop()
      state:push( getmetatable(left).__add(left, right, env) )
   end,
   [ops.BI_SUB] = function(env, state)
      local right = state:pop()
      local left = state:pop()
      state:push( getmetatable(left).__sub(left, right, env) )
   end,
   [ops.BI_MUL] = nyi('BI_MUL'),
   [ops.BI_DIV] = nyi('BI_DIV')
}

function Env:interpretOne(state)
   local op = state:getnext()
   -- print(state.pc, ops.bynum[op])
   local nstate = one_step[op](self, state) or state
   return nstate
end

function Env:interpret(modul, func_id, frame)
   local frame2 = frame
   if frame2 == nil then
      frame2 = self:makeTopLevelFrame(jsval.Null, {})
   end
   local func = modul.functions[func_id + 1] -- 1-based indexing
   local top = State:new(nil, frame2, modul, func)
   local state = State:new(top, frame2, modul, func)
   while state.parent ~= nil do -- wait for state == top
      state = self:interpretOne(state)
   end
   return state:pop()
end

return Env
