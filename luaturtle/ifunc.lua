local ifunc = {}

local Function = {
   type = 'Function'
}
Function.__index = Function

function Function:new(o)
   setmetatable(o, self)
   return o
end


ifunc.Function = Function
return ifunc
