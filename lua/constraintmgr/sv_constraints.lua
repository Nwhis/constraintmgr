local cAdvBallsocket = function(n) return constraint.AdvBallsocket(n.ent1,n.ent2,n.bone1,n.bone2,n.lpos1,n.lpos2,n.forcelimit,n.torquelimit,n.xmin,n.ymin,n.zmin,n.xmax,n.ymax,n.zmax,n.xfric,n.yfric,n.zfric,n.onlyrotation,n.nocollide) end
local cAxis = function(n) return constraint.Axis(n.ent1,n.ent2,n.bone1,n.bone2,n.lpos1,n.lpos2,n.forcelimit,n.torquelimit,n.friction,n.nocollide,n.localaxis) end
local cBallsocket = function(n) return constraint.Ballsocket(n.ent1,n.ent2,n.bone1,n.bone2,n.lpos,n.forcelimit,n.torquelimit,n.nocollide) end
local cElastic = function(n) return constraint.Elastic(n.ent1,n.ent2,n.bone1,n.bone2,n.lpos1,n.lpos2,n.constant,n.damping,n.rdamping,n.material,n.width,n.stretchonly,n.color) end
local cKeepupright = function(n) return constraint.Keepupright(n.ent1,n.ang,n.bone,n.angularlimit) end
local cHydraulic = function(n) return constraint.Hydraulic(n.pl,n.ent1,n.ent2,n.bone1,n.bone2,n.lpos1,n.lpos2,n.length1,n.length2,n.width,n.key,n.fixed,n.speed,n.material,n.toggle,n.color) end
local cMotor = function(n) return constraint.Motor(n.ent1,n.ent2,n.bone1,n.bone2,n.lpos1,n.lpos2,n.friction,n.torque,n.forcetime,n.nocollide,n.toggle,n.pl,n.forcelimit,n.numpadkey_fwd,n.numpadkey_bwd,n.direction,n.localaxis) end
local cMuscle = function(n) return constraint.Muscle(n.pl,n.ent1,n.ent2,n.bone1,n.bone2,n.lpos1,n.lpos2,n.length1,n.length2,n.width,n.key,n.fixed,n.period,n.amplitude,n.starton,n.material,n.color) end
local cPulley = function(n) return constraint.Pulley(n.ent1,n.ent4,n.bone1,n.bone4,n.lpos1,n.lpos4,n.wpos2,n.wpos3,n.forcelimit,n.rigid,n.width,n.material,n.color) end
local cRope = function(n) return constraint.Rope(n.ent1,n.ent2,n.bone1,n.bone2,n.lpos1,n.lpos2,n.length,n.addlength,n.forcelimit,n.width,n.material,n.rigid,n.color) end
local cSlider = function(n) return constraint.Slider(n.ent1,n.ent2,n.bone1,n.bone2,n.lpos1,n.lpos2,n.width,n.material,n.color) end
local cWeld = function(n) return constraint.Weld(n.ent1,n.ent2,n.bone1,n.bone2,n.forcelimit,n.nocollide,n.deleteent1onbreak) end
local cWinch = function(n) return constraint.Winch(n.pl,n.ent1,n.ent2,n.bone1,n.bone2,n.lpos1,n.lpos2,n.width,n.fwd_bind,n.bwd_bind,n.fwd_speed,n.bwd_speed,n.material,n.toggle,n.color) end
local function UpdateWireConstraint(controller,const,const2) -- helper function to update wire constraint controllers
    const.MyCrtl = controller:EntIndex()

    controller:DontDeleteOnRemove(controller.constraint)
    controller.constraint:DontDeleteOnRemove(controller)
    if controller.const2 then controller:DontDeleteOnRemove(controller.const2) end

    controller:SetConstraint( const, const2 )
    controller:DeleteOnRemove( const )
    if const2 then controller:DeleteOnRemove( const2 ) end

    const:DeleteOnRemove( controller )
end
local cWireHydraulic = function(n)
    local const,rope = MakeWireHydraulic(n.pl,n.ent1,n.ent2,n.bone1,n.bone2,n.lpos1,n.lpos2,n.width,n.material,n.speed,n.fixed,tobool(n.stretchonly))
    UpdateWireConstraint(Entity(n.mycrtl),const,rope)
    return const
end
local cWireMotor = function(n)
    local const,axis = MakeWireMotor(n.pl,n.ent1,n.ent2,n.bone1,n.bone2,n.lpos1,n.lpos2,n.friction,n.torque,n.nocollide,n.forcelimit)
    UpdateWireConstraint(Entity(n.mycrtl),const,axis)
    return const
end
local funcs = {
    AdvBallsocket = cAdvBallsocket,
    Axis = cAxis,
    Ballsocket = cBallsocket,
    Elastic = cElastic,
    Hydraulic = cHydraulic,
    Keepupright = cKeepupright,
    Motor = cMotor,
    Muscle = cMuscle,
    Pulley = cPulley,
    Rope = cRope,
    Slider = cSlider,
    Weld = cWeld,
    Winch = cWinch,
    WireHydraulic = cWireHydraulic,
    WireMotor = cWireMotor
}
local function CreateConstraint(func,tbl)
    func = funcs[func]
    if not func then return false end
    tbl = table.LowerKeyNames(tbl)
    local c = func(tbl)
    return c and c or false
end
function CMgr.NewConstraint(oldType,n)
    if n.length then n.length = math.max(n.length,0) end -- fix up odd values
    if n.addlength then n.length = n.length + n.addlength n.addlength = 0 end
    if n.fwd_speed then n.speed = n.fwd_speed end

    local world2 = n.Ent2 and n.Ent2:IsWorld() and not n.Ent1:IsWorld() -- swap ents/positions if ent2 is immovable
    local f_ent1, f_ent2 = n.Ent1, n.Ent2
    local f_lpos1, f_lpos2 = n.LPos1, n.LPos2
    if world2 then
        f_ent1, f_ent2 = n.Ent2, n.Ent1
        f_lpos1, f_lpos2 = n.LPos2, n.LPos1
    end

    local pos2 = n.Ent2 and f_ent2:GetPos() or nil
    if n.length then -- maintain (or set) correct constraint length
        local wpos1,wpos2 = f_ent1:LocalToWorld(f_lpos1),f_ent2:LocalToWorld(f_lpos2)
        local gowpos2 = wpos2 - pos2
        f_ent2:SetPos(wpos1 - gowpos2 + Vector(n.length,0,0))
    end
    local c = CreateConstraint(oldType,n)
    if n.length then f_ent2:SetPos(pos2) end
    return c
end