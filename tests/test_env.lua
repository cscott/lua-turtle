local lu = require('luaunit')
local jsval = require('luaturtle.jsval')
local ifunc = require('luaturtle.ifunc')
local modul = require('luaturtle.module')
local ops = require('luaturtle.ops')
local Env = require('luaturtle.env')

local TestEnv = {}

function TestEnv.testBasic()
   -- Extremely basic module, just '{ return 1+2; }'
   local env = Env:new()
   local functions = {
      ifunc.Function:new{
         name = jsval.Undefined,
         id = 0,
         nargs = 0,
         max_stack = 2,
         bytecode = {
            ops.PUSH_LITERAL, 0,     -- 0: push_literal(0)
            ops.PUSH_LITERAL, 1,     -- 2: push_literal(1)
            ops.BI_ADD,       -- 4: bi_add
            ops.RETURN        -- 5: return
         }
      }
   }
   local literals = {
      jsval.newNumber(1), -- 0
      jsval.newNumber(2) -- 1
   }
   local m = modul:new{ functions = functions, literals = literals }
   local frame = env:makeTopLevelFrame( jsval.Null, {} )
   local result = env:interpret( m, 0, frame )
   lu.assertEquals( tostring(result), '3')
   lu.assertEquals( jsval.Type(result), 'Number')
end

function TestEnv.testMixedTypes()
   -- Test mixed type addition '{ return 1+'x'; }'
   local env = Env:new()
   local functions = {
      ifunc.Function:new{
         name = jsval.Undefined,
         id = 0,
         nargs = 0,
         max_stack = 2,
         bytecode = {
            ops.PUSH_LITERAL, 0,     -- 0: push_literal(0)
            ops.PUSH_LITERAL, 1,     -- 2: push_literal(1)
            ops.BI_ADD,       -- 4: bi_add
            ops.RETURN        -- 5: return
         }
      }
   }
   local literals = {
      jsval.newNumber(1), -- 0
      jsval.newString("x") -- 1
   }
   local m = modul:new{ functions = functions, literals = literals }
   local frame = env:makeTopLevelFrame( jsval.Null, {} )
   local result = env:interpret( m, 0, frame )
   lu.assertEquals( tostring(result), '1x')
   lu.assertEquals( jsval.Type(result), 'String')
end

function TestEnv.testFib()
   -- Slightly more interesting module:
   -- { var fib=function(n){return (n<2)?1:fib(n-1)+fib(n-2);}; return fib(10); }
   local env = Env:new()
   local functions = {
      ifunc.Function:new{
         name = jsval.Undefined,
         id = 0,
         nargs = 0,
         max_stack = 3,
         bytecode = {
            ops.PUSH_FRAME,          -- 0: push_frame
            ops.PUSH_LITERAL, 0,     -- 1: push_literal(0)
            ops.SET_SLOT_DIRECT, 1,  -- 3: set_slot_direct(1)
            ops.PUSH_FRAME,          -- 5: push_frame
            ops.NEW_FUNCTION, 1,     -- 6: new_function(1)
            ops.SET_SLOT_DIRECT, 1,  -- 8: set_slot_direct(1)
            ops.PUSH_FRAME,          -- 10: push_frame
            ops.GET_SLOT_DIRECT, 1,  -- 11: get_slot_direct(1)
            ops.PUSH_LOCAL_FRAME,    -- 13: push_local_frame
            ops.GET_SLOT_DIRECT, 7,  -- 14: get_slot_direct(7)
            ops.PUSH_LITERAL, 8,     -- 16: push_literal(8)
            ops.INVOKE, 1,           -- 18: invoke(1)
            ops.RETURN               -- 20: return
         }
      },
      ifunc.Function:new{ -- "fib"
         name = jsval.newString("fib"),
         id = 1,
         nargs = 1,
         max_stack = 5,
         bytecode = {
            ops.PUSH_LOCAL_FRAME,    -- 0: push_local_frame
            ops.GET_SLOT_DIRECT, 2,  -- 1: get_slot_direct(2)
            ops.DUP,                 -- 3: dup
            ops.GET_SLOT_DIRECT, 3,  -- 4: get_slot_direct(3)
            ops.PUSH_LOCAL_FRAME,    -- 6: push_local_frame
            ops.SWAP,                -- 7: swap
            ops.SET_SLOT_DIRECT, 4,  -- 8: set_slot_direct(4)
            ops.POP,                 -- 10: pop
            ops.PUSH_LOCAL_FRAME,    -- 11: push_local_frame
            ops.GET_SLOT_DIRECT, 4,  -- 12: get_slot_direct(4)
            ops.PUSH_LITERAL, 5,     -- 14: push_literal(5)
            ops.SWAP,                -- 16: swap
            ops.BI_GT,               -- 17: bi_gt
            ops.JMP_UNLESS, 25, 54,  -- 18: jmp_unless(25,54)
            ops.PUSH_LITERAL, 6,     -- 21: push_literal(6)
            ops.JMP, 54,             -- 23: jmp(54)
            ops.PUSH_FRAME,          -- 25: push_frame
            ops.GET_SLOT_DIRECT, 1,  -- 26: get_slot_direct(1)
            ops.PUSH_LOCAL_FRAME,    -- 28: push_local_frame
            ops.GET_SLOT_DIRECT, 7,  -- 29: get_slot_direct(7)
            ops.PUSH_LOCAL_FRAME,    -- 31: push_local_frame
            ops.GET_SLOT_DIRECT, 4,  -- 32: get_slot_direct(4)
            ops.PUSH_LITERAL, 6,     -- 34: push_literal(6)
            ops.BI_SUB,              -- 36: bi_sub
            ops.INVOKE, 1,           -- 37: invoke(1)
            ops.PUSH_FRAME,          -- 39: push_frame
            ops.GET_SLOT_DIRECT, 1,  -- 40: get_slot_direct(1)
            ops.PUSH_LOCAL_FRAME,    -- 42: push_local_frame
            ops.GET_SLOT_DIRECT, 7,  -- 43: get_slot_direct(7)
            ops.PUSH_LOCAL_FRAME,    -- 45: push_local_frame
            ops.GET_SLOT_DIRECT, 4,  -- 46: get_slot_direct(4)
            ops.PUSH_LITERAL, 5,     -- 48: push_literal(5)
            ops.BI_SUB,              -- 50: bi_sub
            ops.INVOKE, 1,           -- 51: invoke(1)
            ops.BI_ADD,              -- 53: bi_add
            ops.PHI,                 -- 54: phi
            ops.RETURN               -- 55: return
         }
      }
   }
   local literals = {
      jsval.Undefined, -- 0
      jsval.newString("fib"), -- 1
      jsval.newString("arguments"), -- 2
      jsval.newNumber(0), -- 3
      jsval.newString("n"), -- 4
      jsval.newNumber(2), -- 5
      jsval.newNumber(1), -- 6
      jsval.newString("this"), -- 7
      jsval.newNumber(10) -- 8
   }
   local m = modul:new{ functions = functions, literals = literals }
   local frame = env:makeTopLevelFrame( jsval.Null, {} )
   local result = env:interpret( m, 0, frame )
   lu.assertEquals( tostring(result), '89')
   lu.assertEquals( jsval.Type(result), 'Number')
end

return TestEnv
