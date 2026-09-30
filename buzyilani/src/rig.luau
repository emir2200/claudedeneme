-- ─────────────────────────────────────────────────────────────────────────────
-- Buz yılanının iskeleti ve animasyon mantığı.
--
-- Bu dosya, build.luau'nun ürettiği veri tablosunun (Rig.bones, Rig.parts, Rig.body)
-- ALTINA eklenir ve birlikte "YilanRig" ModuleScript'ini oluşturur. Yalnızca
-- CFrame/Vector3/math kullanır; Roblox servislerine dokunmaz, bu sayede aynı kod
-- Lune ile bilgisayarda da test edilir.
--
-- Kemikler: her kemiğin dinlenme pivotu vardır; dinlenme yönelimi dünya eksenleriyle
-- aynıdır. Pozdaki dönüşler kemiğin kendi pivotu etrafında uygulanır:
--   X ekseni = geriye/öne yatırma, Y = sağa sola (yerde kayma), Z = yana yatırma.
-- Yerdeki halkanın kemikleri yalnızca dikey eksende döner; böylece gövde yerden kalkmadan
-- yerde kayar. Model -Z yönüne bakar (Roblox'un "ön" yönü).
-- ─────────────────────────────────────────────────────────────────────────────

local TAU = math.pi * 2
local A = CFrame.Angles

Rig.ROAR_DURATION = 4.0
Rig.ROAR_INTERVAL = 14
Rig.BREATH_PERIOD = 4.0
Rig.TONGUE_PERIOD = 5.5

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
--- 0.0–1.0 sn hazırlık (boyun geriye kıvrılır), 1.0–3.2 sn saldırı ve buz nefesi, 3.2–4.0 sn sakinleşme.
function Rig.roarEnvelope(rt: number?): (number, number)
	if rt == nil or rt < 0 or rt > Rig.ROAR_DURATION then
		return 0, 0
	end
	local windup = smooth(rt / 1.0) * (1 - smooth((rt - 1.0) / 0.3))
	local roar = smooth((rt - 1.0) / 0.3) * (1 - smooth((rt - 3.2) / 0.8))
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

--- Nefes verme şiddeti (0..1): burundan buhar çıktığı an.
function Rig.exhale(t: number): number
	return math.max(0, -math.cos(t * TAU / Rig.BREATH_PERIOD))
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

	for _, b in Rig.body do
		if b.kind == "tail" then
			-- Kuyruk ucu: yavaşça kıvrılıp açılır; uca doğru dalga büyür. Kükrerken titrer.
			local amp = 0.03 + 0.03 * b.order
			p[b.bone] = A(0, amp * math.sin(t * 1.3 - b.order * 0.8) + roar * 0.06 * math.sin(t * 22 + b.order), 0)
		elseif b.kind == "coil" then
			-- Yerdeki halka: gövde boyunca ilerleyen çok hafif kayma dalgası.
			p[b.bone] = A(0, 0.006 * math.sin(t * 0.8 - b.order * 0.6) + roar * 0.004 * math.sin(t * 5 - b.order), 0)
		else
			-- Boyun: nefesle hafifçe salınır; hazırlıkta geriye kıvrılır, saldırıda öne atılır.
			local k = b.order / b.count
			local sway = 0.03 * math.sin(t * 0.5 - b.order * 0.35)
			local pitch = calm * (0.012 * breath + 0.02 * math.sin(t * 0.37 - b.order * 0.5))
				+ windup * (0.05 + 0.07 * k) - roar * (0.04 + 0.03 * k)
			p[b.bone] = A(pitch, calm * sway + roar * 0.025 * math.sin(t * 6 - b.order), 0)
		end
	end

	-- Baş: etrafı süzer; hazırlıkta yukarı kalkar, saldırıda öne bakacak şekilde kalkıp ağzını açar.
	local look = math.sin(t * 0.33) * 0.26 + math.sin(t * 0.9) * 0.07
	local nod = math.sin(t * 0.45) * 0.06
	set("head", A(calm * nod + windup * 0.22 + roar * 0.5, calm * look + roar * 0.06 * math.sin(t * 7), roar * 0.05 * math.sin(t * 5.5)))
	set("jaw", A(-(0.02 + windup * 0.0 + roar * (0.55 + 0.05 * math.sin(t * 14))), 0, 0))

	-- Çatal dil: birkaç saniyede bir iki kez hızla dışarı çıkıp titrer.
	local cycle = t % Rig.TONGUE_PERIOD
	local out = (bump(cycle, 0, 0.45, 0.12) + bump(cycle, 0.55, 1.0, 0.12)) * calm
	set("tongue", CFrame.new(0, 0, -2.4 * out) * A(0.25 * math.sin(t * 38) * out, 0.1 * math.sin(t * 29) * out, 0))
	return p
end

--- Pozdan, kemiklerin model uzayındaki CFrame'lerini hesaplar. `scale` Model:GetScale().
--- Poz dönüşleri öteleme de içerebilir (dil öne kayar); öteleme de ölçeklenir.
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

return Rig
