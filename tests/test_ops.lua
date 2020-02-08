local lu = require('luaunit')
local ops = require('luaturtle.ops')

local TestOps = {}

function TestOps.testPushLiteral()
   lu.assertEquals(ops.byname.PUSH_LITERAL, 1)
   lu.assertEquals(ops.bynum[1], 'PUSH_LITERAL')
   lu.assertEquals(ops.PUSH_LITERAL, ops.byname.PUSH_LITERAL)
end

function TestOps.testInvoke()
   lu.assertEquals(ops.byname.INVOKE, 10)
   lu.assertEquals(ops.bynum[10], 'INVOKE')
   lu.assertEquals(ops.INVOKE, ops.byname.INVOKE)
end


return TestOps
