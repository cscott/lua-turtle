#!/usr/bin/env lua
lu = require('luaunit')

TestOps = require('tests.test_ops')
TestJsVal = require('tests.test_jsval')
TestEnv = require('tests.test_env')
TestInterp = require('tests.test_interp')

os.exit(lu.LuaUnit.run())
