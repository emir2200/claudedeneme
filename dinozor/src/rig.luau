-- ─────────────────────────────────────────────────────────────────────────────
-- Lav dinozorunun iskeleti ve animasyon mantığı.
--
-- Bu dosya, build.luau'nun ürettiği veri tablosunun (Rig.bones, Rig.parts,
-- Rig.glowGroups, Rig.drips) ALTINA eklenir ve birlikte "DinozorRig"
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

Rig.ROAR_DURATION = 4.0
Rig.ROAR_INTERVAL = 12
Rig.BREATH_PERIOD = 3.2

Rig.boneIndex = {}
for i, b in Rig.bones do
	Rig.boneIndex[b.name] = i
end

local function smooth(x: number): number
	x = math.clamp(x, 0, 1)
	return x * x * (3 - 2 * x)
end

--- Kükreme başlangıcından bu yana geçen süre `rt` için (hazırlık, kükreme) şiddetleri, 0..1.
--- 0.0–0.8 sn hazırlık (baş kalkar, ağız kapanır), 0.8–3.2 sn kükreme ve alev, 3.2–4.0 sn sakinleşme.
function Rig.roarEnvelope(rt: number?): (number, number)
	if rt == nil or rt < 0 or rt > Rig.ROAR_DURATION then
		return 0, 0
	end
	local windup = smooth(rt / 0.8) * (1 - smooth((rt - 0.8) / 0.35))
	local roar = smooth((rt - 0.8) / 0.35) * (1 - smooth((rt - 3.2) / 0.8))
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
		local rt = (now + 4) % interval
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

	-- Gövde: nefes alıp verme; hazırlıkta göğsünü kaldırır, kükrerken öne atılır.
	set("spine1", A(0.015 * breath + 0.05 * windup - 0.035 * roar, 0.025 * math.sin(t * 0.33) * calm, 0))
	set("chest", A(0.012 * math.sin(t * TAU / Rig.BREATH_PERIOD + 0.5) + 0.05 * windup - 0.03 * roar, 0.03 * math.sin(t * 0.41 + 1) * calm, 0))

	-- Boyun ve baş: sakinken etrafı süzer; hazırlıkta başını kaldırır; kükrerken ileri uzatıp sallar.
	local look = math.sin(t * 0.29) * 0.22 + math.sin(t * 0.71) * 0.06
	local nod = math.sin(t * 0.53) * 0.035
	local shake = roar * 0.07 * math.sin(t * 8.5)
	for _, name in { "neck1", "neck2" } do
		set(name, A(calm * nod + windup * 0.16 - roar * 0.03, calm * look / 3 + shake, 0))
	end
	set("head", A(calm * (nod - 0.02) + windup * 0.14 - roar * 0.02, calm * look / 3 + shake, roar * 0.05 * math.sin(t * 6.5)))
	-- Çene: negatif X aşağı açar. Sakinken ağız aralıktır, içindeki lav görünür.
	local idleJaw = 0.14 + 0.06 * (breath + 1) / 2 + 0.05 * math.max(0, math.sin(t * 0.9)) ^ 8
	set("jaw", A(-(idleJaw * calm + roar * (0.74 + 0.05 * math.sin(t * 16)) + windup * 0.04), 0, 0))

	-- Kuyruk: uca doğru gecikmeli dalga; kükrerken kalkar ve kamçılanır.
	for i = 1, 7 do
		local wave = math.sin(t * 0.95 - i * 0.5)
		set("tail" .. i, A(0.012 * math.sin(t * 0.7 - i * 0.45) - 0.035 * roar + 0.02 * windup, (0.05 + 0.06 * roar) * wave + roar * 0.04 * math.sin(t * 5 - i * 0.8), 0))
	end

	-- Kısa ön kollar: seğirir; kükrerken öne kalkar, pençeler açılır.
	for side, sgn in { L = 1, R = -1 } do
		local twitch = math.sin(t * 1.2 + (if sgn > 0 then 0 else 2.1))
		set("arm" .. side, A(0.12 * twitch * calm + 0.4 * roar - 0.2 * windup, 0, sgn * 0.12 * roar))
		set("forearm" .. side, A(-0.15 * twitch * calm - 0.3 * roar, 0, 0))
		set("hand" .. side, A(0.2 * math.sin(t * 1.7 + sgn) * calm - 0.3 * roar, 0, 0))
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

--- Lav çatlaklarının parlaklığı, 0..1. `phase` parçanın göğüsten uzaklığına bağlı gecikmedir:
--- nabız ve kükremedeki parlama göğüsten başa, bacaklara ve kuyruk ucuna doğru dalga gibi yayılır.
function Rig.glow(t: number, rt: number?, phase: number): number
	local windup, roar = Rig.roarEnvelope(if rt then rt - phase * 0.5 else nil)
	local pulse = 0.5 + 0.5 * math.sin((t - phase) * TAU / Rig.BREATH_PERIOD)
	local flicker = 0.06 * math.sin(t * 5.3 + phase * 11) * math.sin(t * 3.1 + phase * 5)
	return math.clamp(0.28 + 0.34 * pulse + flicker + 0.4 * math.max(roar, windup * 0.5) + roar * 0.1 * math.sin(t * 19 + phase * 9), 0, 1)
end

--- Damlanın boy oranı (0..1) ve kaçıncı damla olduğu: uzar, uzar, kopar ve baştan başlar.
function Rig.dripCycle(t: number, period: number, phase: number): (number, number)
	local c = t / period + phase
	local n = math.floor(c)
	local f = c - n
	return 0.3 + 0.7 * f * f, n
end

return Rig
