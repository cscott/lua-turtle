local lu = require('luaunit')
local ops = require('luaturtle.ops')

local TestOps = {}

function TestOps.testPushLiteral()
   lu.assertEquals(ops.byname.PUSH_LITERAL, 2)
   lu.assertEquals(ops.bynum[2], 'PUSH_LITERAL')
   lu.assertEquals(ops.PUSH_LITERAL, ops.byname.PUSH_LITERAL)
end

function TestOps.testInvoke()
   lu.assertEquals(ops.byname.INVOKE, 11)
   lu.assertEquals(ops.bynum[11], 'INVOKE')
   lu.assertEquals(ops.INVOKE, ops.byname.INVOKE)
end


return TestOps
