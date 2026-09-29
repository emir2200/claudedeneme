-- ─────────────────────────────────────────────────────────────────────────────
-- Üç başlı ejderhanın iskeleti ve animasyon mantığı.
--
-- Bu dosya, build.luau'nun ürettiği veri tablosunun (Rig.bones, Rig.parts,
-- Rig.membranes, Rig.bolts) ALTINA eklenir ve birlikte "UcBasliRig"
-- ModuleScript'ini oluşturur. Yalnızca CFrame/Vector3/math kullanır; Roblox
-- servislerine dokunmaz, bu sayede aynı kod Lune ile bilgisayarda da test edilir.
--
-- Kemikler: her kemiğin dinlenme pivotu vardır; dinlenme yönelimi dünya eksenleriyle
-- aynıdır. Pozdaki dönüşler kemiğin kendi pivotu etrafında uygulanır:
--   X ekseni = kaldırma/indirme (boyunlarda geriye/öne yatırma), Y = sağa sola çevirme,
--   Z = yana yatırma. Model -Z yönüne bakar (Roblox'un "ön" yönü).
-- Başlar: M = ortadaki, L = modelin solundaki (+X), R = sağındaki (-X).
-- ─────────────────────────────────────────────────────────────────────────────

local TAU = math.pi * 2
local A = CFrame.Angles

Rig.ROAR_DURATION = 4.2
Rig.ROAR_INTERVAL = 15
Rig.BREATH_PERIOD = 3.6
Rig.BICKER_PERIOD = 11

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

--- Kükreme başlangıcından bu yana geçen süre `rt` için (hazırlık, kükreme) şiddetleri, 0..1.
--- 0.0–0.9 sn hazırlık (üç baş birden geri kalkar), 0.9–3.4 sn kükreme ve altın şimşekler,
--- 3.4–4.2 sn sakinleşme.
function Rig.roarEnvelope(rt: number?): (number, number)
	if rt == nil or rt < 0 or rt > Rig.ROAR_DURATION then
		return 0, 0
	end
	local windup = smooth(rt / 0.9) * (1 - smooth((rt - 0.9) / 0.35))
	local roar = smooth((rt - 0.9) / 0.35) * (1 - smooth((rt - 3.4) / 0.8))
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
		local rt = (now + 6) % interval
		if rt <= Rig.ROAR_DURATION then
			return rt
		end
	end
	return nil
end

-- Her başın kendi karakteri: faz farkı, taraf (+1 sol, -1 sağ, 0 orta).
local HEADS = {
	{ key = "M", side = 0, phase = 0 },
	{ key = "L", side = 1, phase = 2.1 },
	{ key = "R", side = -1, phase = 4.4 },
}
-- Boyun dönüşünün kemiklere dağılımı (tabandan başa).
local NECK_SHARE = { 0.15, 0.2, 0.25, 0.2 }

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

	-- Gövde: nefes; hazırlıkta geriye kasılır, kükrerken göğsünü öne çıkarır.
	set("spine1", A(0.02 * breath + 0.05 * windup - 0.05 * roar, 0, 0))
	set("chest", A(0.018 * math.sin(t * TAU / Rig.BREATH_PERIOD + 0.6) + 0.05 * windup - 0.06 * roar, 0.025 * math.sin(t * 0.37) * calm, 0))

	-- Boyunlar ve başlar: her baş kendi başına etrafı süzer. Yan başlar ara sıra ortadakine
	-- dönüp çenelerini şaklatır (atışma). Hazırlıkta üçü birden geri kalkar, kükrerken öne
	-- uzanıp yana açılır.
	local bickerTime = t % Rig.BICKER_PERIOD
	for _, h in HEADS do
		local look = math.sin(t * 0.31 + h.phase) * 0.22 + math.sin(t * 0.77 + h.phase * 1.7) * 0.07
		local nod = math.sin(t * 0.47 + h.phase) * 0.05
		local bicker = if h.side ~= 0 then bump(bickerTime, 5.5 + h.side * 0.3, 8.0 + h.side * 0.3, 0.6) * calm else 0
		local yaw = calm * look + h.side * (0.55 * bicker - 0.2 * roar)
		local pitch = calm * nod + 0.1 * bicker + windup * 0.12 - roar * 0.02
		local shake = roar * 0.05 * math.sin(t * 8 + h.phase)
		for i, share in NECK_SHARE do
			set("neck" .. h.key .. i, A(pitch + shake * 0.5, yaw * share + shake, 0))
		end
		set("head" .. h.key, A(calm * (nod - 0.04) + windup * 0.12 - roar * 0.05, yaw * 0.2 + shake, roar * 0.06 * math.sin(t * 6 + h.phase)))
		-- Çene: negatif X aşağı açar. Atışırken şaklar, kükrerken sonuna kadar açılır.
		local idleJaw = 0.05 + 0.04 * (math.sin(t * 0.9 + h.phase) + 1) / 2
		local snap = bicker * 0.4 * math.abs(math.sin(t * 7 + h.phase))
		set("jaw" .. h.key, A(-(idleJaw * calm + snap + roar * (0.6 + 0.05 * math.sin(t * 15 + h.phase)) + windup * 0.02), 0, 0))
	end

	-- Kanatlar: omuzdan kalkıp inme (Z), elden dalga; kükrerken daha hızlı ve geniş açılır.
	local flap = t * TAU / (3.2 - 1.0 * roar)
	local amp = 0.14 + 0.2 * roar
	for side, sgn in { L = 1, R = -1 } do
		local lift = math.sin(flap) * amp + 0.18 * roar + 0.1 * windup
		set("wingRoot" .. side, A(0.04 * math.sin(flap + 0.5), sgn * (0.12 * roar - 0.05 * windup), sgn * lift))
		set("wingElbow" .. side, A(0, sgn * 0.05 * math.sin(flap - 0.4), -sgn * 0.5 * math.sin(flap - 0.7) * amp))
		set("wingWrist" .. side, A(0, sgn * (0.06 * math.sin(flap - 1.0) + 0.1 * roar), -sgn * 0.35 * math.sin(flap - 1.1) * amp))
		for f = 1, 4 do
			set("finger" .. side .. f, A(0, 0, sgn * (0.04 * math.sin(flap - 1.3 - f * 0.2) + 0.03 * roar * (f - 2.5))))
		end
	end

	-- İki kuyruk: ters fazlı dalgalar; kükrerken kalkıp kamçılanır.
	for side, offset in { L = 0, R = math.pi } do
		for i = 1, 6 do
			local wave = math.sin(t * 1.0 - i * 0.5 + offset)
			set("tail" .. side .. i, A(-0.03 * roar + 0.02 * math.sin(t * 0.8 - i * 0.4 + offset), (0.06 + 0.08 * roar) * wave + roar * 0.05 * math.sin(t * 6 - i + offset), 0))
		end
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

--- Kükremedeki altın şimşeklerin boyu oranı (0..1): kükreme başlarken ağızdan dışarı uzar.
function Rig.boltReach(rt: number?): number
	local _, roar = Rig.roarEnvelope(rt)
	return smooth((roar - 0.3) / 0.5)
end

return Rig
