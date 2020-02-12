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
            ops.PUSH_FRAME,        -- 0: push_frame
            ops.PUSH_LITERAL, 0,     -- 1: push_literal(0)
            ops.SET_SLOT_DIRECT, 1,     -- 3: set_slot_direct(1)
            ops.PUSH_FRAME,        -- 5: push_frame
            ops.NEW_FUNCTION, 1,     -- 6: new_function(1)
            ops.SET_SLOT_DIRECT, 1,     -- 8: set_slot_direct(1)
            ops.PUSH_FRAME,        -- 10: push_frame
            ops.GET_SLOT_DIRECT, 1,     -- 11: get_slot_direct(1)
            ops.PUSH_FRAME,        -- 13: push_frame
            ops.GET_SLOT_DIRECT, 8,     -- 14: get_slot_direct(8)
            ops.PUSH_LITERAL, 9,     -- 16: push_literal(9)
            ops.INVOKE, 1,    -- 18: invoke(1)
            ops.RETURN        -- 20: return
         }
      },
      ifunc.Function:new{ -- "fib"
         name = jsval.newString("fib"),
         id = 1,
         nargs = 1,
         max_stack = 5,
         bytecode = {
            ops.PUSH_FRAME,        -- 0: push_frame
            ops.GET_SLOT_DIRECT, 2,     -- 1: get_slot_direct(2)
            ops.DUP,       -- 3: dup
            ops.GET_SLOT_DIRECT, 3,     -- 4: get_slot_direct(3)
            ops.PUSH_FRAME,        -- 6: push_frame
            ops.SWAP,       -- 7: swap
            ops.SET_SLOT_DIRECT, 4,     -- 8: set_slot_direct(4)
            ops.POP,       -- 10: pop
            ops.PUSH_FRAME,        -- 11: push_frame
            ops.GET_SLOT_DIRECT, 4,     -- 12: get_slot_direct(4)
            ops.PUSH_LITERAL, 5,     -- 14: push_literal(5)
            ops.SWAP,       -- 16: swap
            ops.BI_GT,       -- 17: bi_gt
            ops.JMP_UNLESS, 24,   -- 18: jmp_unless(24)
            ops.PUSH_LITERAL, 6,     -- 20: push_literal(6)
            ops.JMP, 57,   -- 22: jmp(57)
            ops.PUSH_FRAME,        -- 24: push_frame
            ops.GET_SLOT_DIRECT, 7,     -- 25: get_slot_direct(7)
            ops.GET_SLOT_DIRECT, 1,     -- 27: get_slot_direct(1)
            ops.PUSH_FRAME,        -- 29: push_frame
            ops.GET_SLOT_DIRECT, 8,     -- 30: get_slot_direct(8)
            ops.PUSH_FRAME,        -- 32: push_frame
            ops.GET_SLOT_DIRECT, 4,     -- 33: get_slot_direct(4)
            ops.PUSH_LITERAL, 6,     -- 35: push_literal(6)
            ops.BI_SUB,       -- 37: bi_sub
            ops.INVOKE, 1,    -- 38: invoke(1)
            ops.PUSH_FRAME,        -- 40: push_frame
            ops.GET_SLOT_DIRECT, 7,     -- 41: get_slot_direct(7)
            ops.GET_SLOT_DIRECT, 1,     -- 43: get_slot_direct(1)
            ops.PUSH_FRAME,        -- 45: push_frame
            ops.GET_SLOT_DIRECT, 8,     -- 46: get_slot_direct(8)
            ops.PUSH_FRAME,        -- 48: push_frame
            ops.GET_SLOT_DIRECT, 4,     -- 49: get_slot_direct(4)
            ops.PUSH_LITERAL, 5,     -- 51: push_literal(5)
            ops.BI_SUB,       -- 53: bi_sub
            ops.INVOKE, 1,    -- 54: invoke(1)
            ops.BI_ADD,       -- 56: bi_add
            ops.RETURN        -- 57: return
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
      jsval.newString("__proto__"), -- 7
      jsval.newString("this"), -- 8
      jsval.newNumber(10) -- 9
   }
   local m = modul:new{ functions = functions, literals = literals }
   local frame = env:makeTopLevelFrame( jsval.Null, {} )
   local result = env:interpret( m, 0, frame )
   lu.assertEquals( tostring(result), '89')
   lu.assertEquals( jsval.Type(result), 'Number')
end

return TestEnv
