#!/usr/bin/env lua
lu = require('luaunit')

TestOps = require('tests.test_ops')
TestJsVal = require('tests.test_jsval')

os.exit(lu.LuaUnit.run())
