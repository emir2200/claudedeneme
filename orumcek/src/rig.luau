-- ─────────────────────────────────────────────────────────────────────────────
-- Orman örümceğinin iskeleti ve animasyon mantığı.
--
-- Bu dosya, build.luau'nun ürettiği veri tablosunun (Rig.bones, Rig.parts, Rig.legs)
-- ALTINA eklenir ve birlikte "OrumcekRig" ModuleScript'ini oluşturur. Yalnızca
-- CFrame/Vector3/math kullanır; Roblox servislerine dokunmaz, bu sayede aynı kod Lune ile
-- bilgisayarda da test edilir.
--
-- Gövde parçaları kemiklere bağlıdır. Bacaklar ise ters kinematikle (IK) çözülür: her
-- bacağın kalçası gövdeyle birlikte hareket eder, ayağı yere basılı kalır; diz, iki parçanın
-- uzunluğuna göre her karede yeniden hesaplanır. Böylece gövde inip kalkarken ayaklar kaymaz.
-- Model -Z yönüne bakar (Roblox'un "ön" yönü).
-- ─────────────────────────────────────────────────────────────────────────────

local TAU = math.pi * 2
local A = CFrame.Angles
local UP = Vector3.new(0, 1, 0)

Rig.ROAR_DURATION = 3.7
Rig.ROAR_INTERVAL = 13
Rig.BREATH_PERIOD = 3.0
Rig.TAP_PERIOD = 9

Rig.boneIndex = {}
for i, b in Rig.bones do
	Rig.boneIndex[b.name] = i
end

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

--- a..b aralığında yumuşakça 0'dan 1'e çıkıp inen tümsek (kenarlarda `edge` sn geçiş).
local function bump(x: number, a: number, b: number, edge: number): number
	return smooth((x - a) / edge) * (1 - smooth((x - (b - edge)) / edge))
end

--- Saldırı başlangıcından bu yana geçen süre `rt` için (hazırlık, saldırı) şiddetleri, 0..1.
--- 0.0–0.9 sn hazırlık (şahlanır, ön bacakları havaya kalkar, dişlerini açar), 0.9–2.9 sn
--- öne atılma ve zehir püskürtme, 2.9–3.7 sn sakinleşme.
function Rig.roarEnvelope(rt: number?): (number, number)
	if rt == nil or rt < 0 or rt > Rig.ROAR_DURATION then
		return 0, 0
	end
	local windup = smooth(rt / 0.9) * (1 - smooth((rt - 0.9) / 0.25))
	local roar = smooth((rt - 0.9) / 0.25) * (1 - smooth((rt - 2.9) / 0.8))
	return windup, roar
end

--- Şu an saldırı sürüyorsa başlangıcından geçen süreyi, sürmüyorsa nil döner.
--- `now` sunucu saatidir; bu sayede bütün oyuncular saldırıyı aynı anda görür.
function Rig.roarTime(now: number, auto: boolean, interval: number, manualStart: number?): number?
	if manualStart then
		local rt = now - manualStart
		if rt >= 0 and rt <= Rig.ROAR_DURATION then
			return rt
		end
	end
	if auto and interval > Rig.ROAR_DURATION then
		local rt = (now + 4) % interval
		if rt <= Rig.ROAR_DURATION then
			return rt
		end
	end
	return nil
end

--- Zaman `t` ve saldırı süresi `rt` için gövde kemiklerinin dönüşleri (kemik sırası → CFrame).
--- Kök kemiğin pozu öteleme de içerir: gövde nefesle inip kalkar, saldırıda şahlanıp öne atılır.
function Rig.pose(t: number, rt: number?): { [number]: CFrame }
	local windup, roar = Rig.roarEnvelope(rt)
	local calm = 1 - math.max(windup, roar)
	local breath = math.sin(t * TAU / Rig.BREATH_PERIOD)
	local p = {}
	local function set(name: string, cf: CFrame)
		local i = Rig.boneIndex[name]
		if i then
			p[i] = cf
		end
	end

	local bob = 0.3 * breath * calm + 0.15 * math.sin(t * 0.7)
	set("govde", CFrame.new(0, bob + windup * 2.4 - roar * 0.5, windup * 0.9 - roar * 1.6)
		* A(0.03 * math.sin(t * 0.6) * calm + windup * 0.3 - roar * 0.12, 0.07 * math.sin(t * 0.27) * calm, 0.03 * math.sin(t * 0.41) * calm))
	-- karın: nefesle hafifçe iner kalkar; şahlanınca aşağı, saldırıda yukarı kalkar
	set("karin", A(0.03 * breath - windup * 0.18 + roar * 0.1, 0.04 * math.sin(t * 0.37) * calm, 0))

	-- Zehir dişleri: ara sıra tıkırdar; hazırlıkta iki yana açılır, saldırıda öne kapanır.
	local click = math.abs(math.sin(t * 6)) * bump(t % 5, 2.0, 3.0, 0.2) * calm
	for side, sgn in { L = 1, R = -1 } do
		set("kiskac" .. side, A(roar * 0.35 - windup * 0.1, 0, sgn * (0.06 + 0.18 * click + windup * 0.5 - roar * 0.05)))
		set("palp" .. side, A(0.2 * math.sin(t * 2.1 + sgn) * calm + windup * 0.5 - roar * 0.2, sgn * 0.12 * math.sin(t * 1.7 + sgn), 0))
	end
	return p
end

--- Dinlenme konumuna göre bacağın bu andaki ayak hedefi (model uzayında).
--- Bacaklar ara sıra kalkıp yere geri basar; hazırlıkta ön iki çift havaya kalkar, saldırıda
--- biraz önde yere çarpar.
function Rig.footTarget(leg, t: number, rt: number?): Vector3
	local windup, roar = Rig.roarEnvelope(rt)
	local calm = 1 - math.max(windup, roar)
	local target = leg.foot
	local cycle = (t + leg.order * 1.7 + (if leg.side > 0 then 0 else 4.3)) % Rig.TAP_PERIOD
	local lift = bump(cycle, 0, 0.8, 0.3) * calm
	target += UP * (2.2 * lift) - leg.outward * (1.2 * lift)
	if leg.order <= 2 then
		local raise = windup * (if leg.order == 1 then 1 else 0.7)
		target += UP * (11 * raise) - leg.outward * (5 * raise) + Vector3.new(0, 0, -3 * raise - 2.5 * roar)
	end
	return target
end

--- -Z'si `look` yönüne bakan, Y'si `upHint`e yakın çerçeve.
function Rig.frame(pos: Vector3, look: Vector3, upHint: Vector3): CFrame
	look = look.Unit
	local right = look:Cross(upHint)
	if right.Magnitude < 1e-4 then
		right = look:Cross(Vector3.new(0, 0, 1))
	end
	right = right.Unit
	return CFrame.fromMatrix(pos, right, right:Cross(look), -look)
end

--- İki parçalı bacak için ters kinematik: kalça `hip`, ayak `foot`, dizin bükülme yönü `pole`.
--- Üst (kalça → diz) ve alt (diz → ayak) parçaların çerçevelerini döner; -Z parça boyunca uzanır.
function Rig.legFrames(hip: Vector3, foot: Vector3, pole: Vector3, l1: number, l2: number): (CFrame, CFrame)
	local toFoot = foot - hip
	local d = math.clamp(toFoot.Magnitude, math.abs(l1 - l2) + 1e-3, l1 + l2 - 1e-3)
	local u = toFoot.Unit
	local v = pole - u * pole:Dot(u)
	v = if v.Magnitude > 1e-4 then v.Unit else UP
	local a = (l1 * l1 - l2 * l2 + d * d) / (2 * d)
	local h = math.sqrt(math.max(0, l1 * l1 - a * a))
	local knee = hip + u * a + v * h
	return Rig.frame(hip, knee - hip, v), Rig.frame(knee, hip + u * d - knee, v)
end

--- Pozdan, kemiklerin model uzayındaki CFrame'lerini hesaplar. `scale` Model:GetScale().
--- Poz öteleme de içerebilir (gövdenin inip kalkması); öteleme de ölçeklenir.
function Rig.solve(pose: { [number]: CFrame }, scale: number): { CFrame }
	local out = table.create(#Rig.bones)
	for i, b in Rig.bones do
		local cf = CFrame.new(b.rel * scale)
		local rot = pose[i]
		if rot then
			cf *= CFrame.new(rot.Position * scale) * rot.Rotation
		end
		out[i] = if b.parent > 0 then out[b.parent] * cf else cf
	end
	return out
end

--- Model uzayında bir bacağın üst ve alt parça çerçeveleri (kemikler çözüldükten sonra).
function Rig.solveLeg(leg, boneCFs: { CFrame }, t: number, rt: number?, scale: number): (CFrame, CFrame)
	local hip = boneCFs[leg.bone] * (leg.hip * scale)
	local foot = Rig.footTarget(leg, t, rt) * scale
	return Rig.legFrames(hip, foot, UP + leg.outward * 0.15, leg.l1 * scale, leg.l2 * scale)
end

return Rig
