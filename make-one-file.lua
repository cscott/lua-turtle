--[[

make-one-file.lua

A helper utility to package up module lua code as a single file.
]]--
local string = require('string')
local debug = require('debug')

function module_name_to_filename(modulename)
   return string.gsub(modulename, "%.", "/") .. ".lua"
end

function top_level(name)
   -- initialize the built-ins as 'seen'
   seen = {}
   seen['table'] = true
   seen['string'] = true
   -- XXX in wrapper code, initialize the built-ins
   modules = process_one(name, module_name_to_filename(name), seen)
   -- emit x
   source = "(function()\n" ..
      "local builders = {}\n" ..
      "function register(name, f)\n" ..
      "  builders[name] = f\n" ..
      "end\n" ..
      modules .. "\n" ..
      "local modules = {}\n" ..
      "modules['table'] = require('table')\n" ..
      "modules['string'] = require('string')\n" ..
      "function myrequire(name)\n" ..
      "  if modules[name] == nil then\n" ..
      "    modules[name] = true\n" ..
      "    modules[name] = (builders[name])(myrequire)\n" ..
      "  end\n" ..
      "  return modules[name]\n" ..
      "end\n" ..
      "return myrequire('" .. name .. "')\n" ..
      "end)()"
   return 'return ' .. source
end

function process_one(name, filename, seen)
   local result = {}
   table.insert(seen, name)
   local source = string.gsub(
      io.input(filename):read('a'),
      'require%(\'([^\']*)\'%)', function(next_name)
         if seen[next_name] == nil then
            next_filename = module_name_to_filename(next_name)
            table.insert(result, process_one(next_name, next_filename, seen))
         end
         -- rewrite all 'require' to 'myrequire'
         return "myrequire('" .. next_name .. "')"
   end)
   -- add wrapper.
   table.insert(result,
                "register('" .. name .. "', function(myrequire)\n" ..
                source .. "\nend)\n")
   -- concatenate everything
   return table.concat(result, "\n")
end

-- Takes one argument, the "module root"
print(top_level(arg[1]))
