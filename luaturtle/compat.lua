-- Compatibility functions
-- (Things present in Lua 5.3 that are missing in Lua 5.1)
local compat = {}

local string = require('string')
local table = require('table')

function compat.combineBytes(msb, lsb)
   -- (msb << 8) | lsb
   return (msb * 256) + lsb
end

function compat.splitBytes(u16)
   -- u16 >> 8, u16 & 0xFF
   local lsb = math.fmod(u16, 256)
   local msb = (u16 - lsb) / 256
   return msb, lsb
end

function compat.rshift(x, disp)
   -- x >> disp
   return math.floor(x/(2^disp))
end

function compat.utf8codes(s)
   local len = #s
   local f = function(state, _)
      local pos = state.nextpos
      if pos > len then
         return nil, nil
      end
      local c1 = string.byte(s, pos)
      if c1 <= 0x7F then
         state.nextpos = pos + 1
         return pos, c1
      end
      c2 = string.byte(s, pos + 1)
      if c1 <= 0xDF then
         state.nextpos = pos + 2
         return pos, ((c1 % 0x20 ) * 0x40) + (c2 % 0x40)
      end
      c3 = string.byte(s, pos + 2)
      if c1 <= 0xEF then
         state.nextpos = pos + 3
         return pos, (((c1 % 0x10) * 0x40) + (c2 % 0x40)) * 0x40 + (c3 % 0x40)
      end
      c4 = string.byte(s, pos + 3)
      if c1 <= 0xF7 then
         state.nextpos = pos + 4
         return pos, ((((c1 % 0x08) * 0x40) + (c2 % 0x40)) * 0x40 + (c3 % 0x40)) * 0x40 + (c4 % 0x40)
      end
      error()
   end
   return f, { nextpos = 1 }, 0
end

function compat.utf8char(...)
   -- utf8.char(c)
   result = {}
   for _,c in ipairs{...} do
      local s
      if c <= 0x7F then
         s = string.char(c)
      else
         c1 = c % 0x40
         cN = (c - c1) / 0x40
         if c <= 0x7FF then
            s = string.char(
               cN + 0xC0,
               c1 + 0x80
            )
         else
            c2 = cN % 0x40
            cN = (cN - c2) / 0x40
            if c <= 0xFFFF then
               s = string.char(
                  cN + 0xE0,
                  c2 + 0x80,
                  c1 + 0x80
               )
            else
               c3 = cN % 0x40
               cN = (cN - c3) / 0x40
               if c <= 0x10FFFF then
                  s = string.char(
                     cN + 0xF0,
                     c3 + 0x80,
                     c2 + 0x80,
                     c1 + 0x80
                  )
               else
                  error()
               end
            end
         end
      end
      table.insert(result, s)
   end
   return table.concat(result)
end

-- unpack is a global function for Lua 5.1, otherwise use table.unpack
compat.unpack = rawget(_G, "unpack") or table.unpack

return compat
