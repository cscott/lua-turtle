local lu = require('luaunit')
local jsval = require('luaturtle.jsval')
local ifunc = require('luaturtle.ifunc')
local modul = require('luaturtle.module')
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
            1, 0,     -- 0: push_literal(0)
            1, 1,     -- 2: push_literal(1)
            26,       -- 4: bi_add
            11        -- 5: return
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
            1, 0,     -- 0: push_literal(0)
            1, 1,     -- 2: push_literal(1)
            26,       -- 4: bi_add
            11        -- 5: return
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

function TestEnv.XtestFib()
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
            0,        -- 0: push_frame
            1, 0,     -- 1: push_literal(0)
            8, 1,     -- 3: set_slot_direct(1)
            0,        -- 5: push_frame
            4, 1,     -- 6: new_function(1)
            8, 1,     -- 8: set_slot_direct(1)
            0,        -- 10: push_frame
            5, 1,     -- 11: get_slot_direct(1)
            0,        -- 13: push_frame
            5, 8,     -- 14: get_slot_direct(8)
            1, 9,     -- 16: push_literal(9)
            10, 1,    -- 18: invoke(1)
            11        -- 20: return
         }
      },
      ifunc.Function:new{ -- "fib"
         name = jsval.newString("fib"),
         id = 1,
         nargs = 1,
         max_stack = 5,
         bytecode = {
            0,        -- 0: push_frame
            5, 2,     -- 1: get_slot_direct(2)
            15,       -- 3: dup
            5, 3,     -- 4: get_slot_direct(3)
            0,        -- 6: push_frame
            19,       -- 7: swap
            8, 4,     -- 8: set_slot_direct(4)
            14,       -- 10: pop
            0,        -- 11: push_frame
            5, 4,     -- 12: get_slot_direct(4)
            1, 5,     -- 14: push_literal(5)
            19,       -- 16: swap
            24,       -- 17: bi_gt
            13, 24,   -- 18: jmp_unless(24)
            1, 6,     -- 20: push_literal(6)
            12, 57,   -- 22: jmp(57)
            0,        -- 24: push_frame
            5, 7,     -- 25: get_slot_direct(7)
            5, 1,     -- 27: get_slot_direct(1)
            0,        -- 29: push_frame
            5, 8,     -- 30: get_slot_direct(8)
            0,        -- 32: push_frame
            5, 4,     -- 33: get_slot_direct(4)
            1, 6,     -- 35: push_literal(6)
            27,       -- 37: bi_sub
            10, 1,    -- 38: invoke(1)
            0,        -- 40: push_frame
            5, 7,     -- 41: get_slot_direct(7)
            5, 1,     -- 43: get_slot_direct(1)
            0,        -- 45: push_frame
            5, 8,     -- 46: get_slot_direct(8)
            0,        -- 48: push_frame
            5, 4,     -- 49: get_slot_direct(4)
            1, 5,     -- 51: push_literal(5)
            27,       -- 53: bi_sub
            10, 1,    -- 54: invoke(1)
            26,       -- 56: bi_add
            11        -- 57: return
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
