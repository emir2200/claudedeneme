-- ─────────────────────────────────────────────────────────────────────────────
-- Ejderha iskeleti ve animasyon mantığı.
--
-- Bu dosya, build.luau'nun ürettiği veri tablosunun (Rig.bones, Rig.parts,
-- Rig.membranes, Rig.glowParts) ALTINA eklenir ve birlikte "EjderhaRig"
-- ModuleScript'ini oluşturur. Yalnızca CFrame/Vector3/math kullanır; Roblox
-- servislerine dokunmaz, bu sayede aynı kod Lune ile bilgisayarda da test edilir.
--
-- Kemikler: her kemiğin dinlenme pivotu vardır; dinlenme yönelimi dünya eksenleriyle
-- aynıdır. Pozdaki dönüşler kemiğin kendi pivotu etrafında uygulanır:
--   X ekseni = başı kaldırma/indirme, Y = sağa sola çevirme, Z = yana yatırma.
-- Model -Z yönüne bakar (Roblox'un "ön" yönü).
-- ─────────────────────────────────────────────────────────────────────────────

local TAU = math.pi * 2
local A = CFrame.Angles

Rig.ROAR_DURATION = 3.8
Rig.ROAR_INTERVAL = 14
Rig.BREATH_PERIOD = 3.4

Rig.boneIndex = {}
for i, b in Rig.bones do
	Rig.boneIndex[b.name] = i
end

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

--- Kükreme başlangıcından bu yana geçen süre `rt` için (hazırlık, kükreme) şiddetleri, 0..1.
--- 0.0–0.7 sn hazırlık (baş geriye kalkar), 0.7–3.0 sn kükreme ve alev, 3.0–3.8 sn sakinleşme.
function Rig.roarEnvelope(rt: number?): (number, number)
	if rt == nil or rt < 0 or rt > Rig.ROAR_DURATION then
		return 0, 0
	end
	local windup = smooth(rt / 0.7) * (1 - smooth((rt - 0.7) / 0.35))
	local roar = smooth((rt - 0.7) / 0.35) * (1 - smooth((rt - 3.0) / 0.8))
	return windup, roar
end

--- Şu an kükreme sürüyorsa başlangıcından geçen süreyi, sürmüyorsa nil döner.
--- `now` sunucu saatidir; bu sayede bütün oyuncular kükremeyi aynı anda görür.
function Rig.roarTime(now: number, auto: boolean, interval: number, manualStart: number?): number?
	if manualStart then
		local rt = now - manualStart
		if rt >= 0 and rt <= Rig.ROAR_DURATION then
			return rt
		end
	end
	if auto and interval > Rig.ROAR_DURATION then
		local rt = (now + 5) % interval
		if rt <= Rig.ROAR_DURATION then
			return rt
		end
	end
	return nil
end

--- Zaman `t` ve kükreme süresi `rt` için kemik dönüşleri (kemik sırası → CFrame).
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

	-- Gövde: nefes alıp verme; hazırlıkta geriye kasılır, kükrerken göğsünü öne çıkarır.
	set("spine1", A(0.025 * breath + 0.05 * windup - 0.05 * roar, 0, 0))
	set("chest", A(0.02 * math.sin(t * TAU / Rig.BREATH_PERIOD + 0.6) + 0.06 * windup - 0.07 * roar, 0.03 * math.sin(t * 0.4) * calm, 0))

	-- Boyun ve baş: sakinken öne bakıp etrafı süzer; hazırlıkta geri kalkar; kükrerken ileri uzanır.
	local look = math.sin(t * 0.37) * 0.16 + math.sin(t * 0.83) * 0.05
	local nod = math.sin(t * 0.61) * 0.04
	for i, name in { "neck1", "neck2", "neck3" } do
		local pitch = calm * (-0.1 + nod) + windup * 0.14 + roar * (0.03 + 0.025 * math.sin(t * 9 + i))
		set(name, A(pitch, calm * look / 3, 0))
	end
	set("head", A(calm * -0.1 + windup * 0.1 - roar * 0.12 + 0.02 * breath, calm * look / 3, 0))
	-- Çene: negatif X aşağı açar.
	local idleJaw = 0.05 + 0.03 * (breath + 1) / 2
	set("jaw", A(-(idleJaw * (1 - roar) + roar * (0.62 + 0.04 * math.sin(t * 17)) + windup * 0.03), 0, 0))

	-- Kanatlar: omuzdan kalkıp inme (Z), elden dalga; kükrerken daha hızlı ve geniş açılır.
	local flap = t * TAU / (2.8 - 0.9 * roar)
	local amp = 0.16 + 0.2 * roar
	for side, sgn in { L = 1, R = -1 } do
		local lift = math.sin(flap) * amp + 0.16 * roar + 0.1 * windup
		set("wingRoot" .. side, A(0.04 * math.sin(flap + 0.5), sgn * (0.1 * roar - 0.05 * windup), sgn * lift))
		set("wingElbow" .. side, A(0, sgn * 0.05 * math.sin(flap - 0.4), -sgn * 0.5 * math.sin(flap - 0.7) * amp))
		set("wingWrist" .. side, A(0, sgn * (0.06 * math.sin(flap - 1.0) + 0.08 * roar), -sgn * 0.35 * math.sin(flap - 1.1) * amp))
		for f = 1, 4 do
			set("finger" .. side .. f, A(0, 0, sgn * (0.04 * math.sin(flap - 1.3 - f * 0.2) + 0.03 * roar * (f - 2.5))))
		end
	end

	-- Kuyruk: uca doğru gecikmeli dalga; kükrerken kalkar ve kamçılanır.
	for i = 1, 6 do
		local wave = math.sin(t * 1.1 - i * 0.55)
		set("tail" .. i, A(-0.02 * roar + 0.02 * math.sin(t * 0.8 - i * 0.4), (0.07 + 0.08 * roar) * wave + roar * 0.05 * math.sin(t * 6 - i), 0))
	end

	-- Ön kollar: pençeler hafifçe açılıp kapanır; kükrerken kollar kalkar.
	for side, sgn in { L = 1, R = -1 } do
		local sway = math.sin(t * 0.9 + (if sgn > 0 then 0 else 1.7))
		set("arm" .. side, A(0.07 * sway * calm + 0.22 * roar - 0.12 * windup, sgn * 0.05 * sway, sgn * 0.08 * roar))
		set("forearm" .. side, A(-0.08 * sway * calm + 0.15 * roar, 0, 0))
		set("hand" .. side, A(0.15 * math.sin(t * 1.3 + sgn) * calm + 0.25 * roar, 0, 0))
	end
	return p
end

--- Pozdan, kemiklerin model uzayındaki CFrame'lerini hesaplar. `scale` Model:GetScale().
function Rig.solve(pose: { [number]: CFrame }, scale: number): { CFrame }
	local out = table.create(#Rig.bones)
	for i, b in Rig.bones do
		local cf = CFrame.new(b.rel * scale)
		local rot = pose[i]
		if rot then
			cf *= rot
		end
		out[i] = if b.parent > 0 then out[b.parent] * cf else cf
	end
	return out
end

--- a, b, c noktalarından geçen üçgeni iki WedgePart ile çizmek için CFrame ve boyutlar.
--- Boyutların X bileşeni (kalınlık) çağıran tarafından verilir. Dejenere üçgende nil döner.
function Rig.triangle(a: Vector3, b: Vector3, c: Vector3): (CFrame?, Vector3?, CFrame?, Vector3?)
	local ab, ac, bc = b - a, c - a, c - b
	local abd, acd, bcd = ab:Dot(ab), ac:Dot(ac), bc:Dot(bc)
	if abd > acd and abd > bcd then
		c, a = a, c
	elseif acd > bcd and acd > abd then
		a, b = b, a
	end
	ab, ac, bc = b - a, c - a, c - b
	local normal = ac:Cross(ab)
	if normal.Magnitude < 1e-6 or bc.Magnitude < 1e-6 then
		return nil, nil, nil, nil
	end
	local right = normal.Unit
	local up = bc:Cross(right).Unit
	local back = bc.Unit
	local height = math.abs(ab:Dot(up))
	return CFrame.fromMatrix((a + b) / 2, right, up, back),
		Vector3.new(0, height, math.abs(ab:Dot(back))),
		CFrame.fromMatrix((a + c) / 2, -right, up, -back),
		Vector3.new(0, height, math.abs(ac:Dot(back)))
end

--- Lav çatlaklarının parlaklığı, 0..1: nefesle atar, kükrerken en parlak hâline çıkar ve titrer.
function Rig.glow(t: number, rt: number?): number
	local windup, roar = Rig.roarEnvelope(rt)
	local pulse = 0.5 + 0.5 * math.sin(t * TAU / Rig.BREATH_PERIOD)
	return math.clamp(0.3 + 0.35 * pulse + 0.35 * math.max(roar, windup * 0.6) + roar * 0.08 * math.sin(t * 23), 0, 1)
end

return Rig
