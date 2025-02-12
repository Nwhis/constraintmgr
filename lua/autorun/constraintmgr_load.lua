AddCSLuaFile("constraintmgr/sh_functions.lua")
AddCSLuaFile("constraintmgr/cl_functions.lua")
AddCSLuaFile("constraintmgr/cl_render.lua")
AddCSLuaFile("constraintmgr/cl_lang.lua")

CMgr = CMgr or {}

include("constraintmgr/sh_functions.lua")
if SERVER then
    include("constraintmgr/sv_functions.lua")
    include("constraintmgr/sv_constraints.lua")
end
if CLIENT then
    include("constraintmgr/cl_functions.lua")
    include("constraintmgr/cl_render.lua")
    include("constraintmgr/cl_lang.lua")
end