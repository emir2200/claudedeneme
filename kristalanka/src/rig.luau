-- ─────────────────────────────────────────────────────────────────────────────
-- Kristal ankanın iskeleti ve animasyon mantığı.
--
-- Bu dosya, build.luau'nun ürettiği veri tablosunun (Rig.bones, Rig.parts) ALTINA
-- eklenir ve birlikte "AnkaRig" ModuleScript'ini oluşturur. Yalnızca CFrame/Vector3/math
-- kullanır; Roblox servislerine dokunmaz, bu sayede aynı kod Lune ile bilgisayarda da
-- test edilir.
--
-- Kemikler: her kemiğin dinlenme pivotu vardır; dinlenme yönelimi dünya eksenleriyle
-- aynıdır. Pozdaki dönüşler kemiğin kendi pivotu etrafında uygulanır:
--   X ekseni = kaldırma/indirme, Y = sağa sola çevirme (kanatta geriye süpürme), Z = yana
--   yatırma (kanadı kaldırıp indirme). Kuş -Z yönüne bakar (Roblox'un "ön" yönü).
-- ─────────────────────────────────────────────────────────────────────────────

local TAU = math.pi * 2
local A = CFrame.Angles

Rig.ROAR_DURATION = 3.6
Rig.ROAR_INTERVAL = 16
Rig.FLAP_PERIOD = 1.5
Rig.GLIDE_PERIOD = 12

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

--- Çığlık başlangıcından bu yana geçen süre `rt` için (hazırlık, çığlık) şiddetleri, 0..1.
--- 0.0–0.7 sn hazırlık (kuş şahlanır, kanatlar yukarı kalkar), 0.7–2.8 sn çığlık ve ışık
--- patlaması, 2.8–3.6 sn sakinleşme.
function Rig.roarEnvelope(rt: number?): (number, number)
	if rt == nil or rt < 0 or rt > Rig.ROAR_DURATION then
		return 0, 0
	end
	local windup = smooth(rt / 0.7) * (1 - smooth((rt - 0.7) / 0.3))
	local roar = smooth((rt - 0.7) / 0.3) * (1 - smooth((rt - 2.8) / 0.8))
	return windup, roar
end

--- Şu an çığlık sürüyorsa başlangıcından geçen süreyi, sürmüyorsa nil döner.
--- `now` sunucu saatidir; bu sayede bütün oyuncular çığlığı aynı anda görür.
function Rig.roarTime(now: number, auto: boolean, interval: number, manualStart: number?): number?
	if manualStart then
		local rt = now - manualStart
		if rt >= 0 and rt <= Rig.ROAR_DURATION then
			return rt
		end
	end
	if auto and interval > Rig.ROAR_DURATION then
		local rt = (now + 7) % interval
		if rt <= Rig.ROAR_DURATION then
			return rt
		end
	end
	return nil
end

--- Kanat çırpma şiddeti: kuş bir süre güçlü çırpar, bir süre kanatları açık süzülür.
function Rig.flapStrength(t: number): number
	return 0.18 + 0.57 * smooth(0.5 + 0.7 * math.sin(t * TAU / Rig.GLIDE_PERIOD))
end

--- Zaman `t` ve çığlık süresi `rt` için kemik dönüşleri (kemik sırası → CFrame).
--- Kök kemiğin pozu öteleme de içerir: kuş kanat vuruşlarıyla birlikte inip kalkar.
function Rig.pose(t: number, rt: number?): { [number]: CFrame }
	local windup, roar = Rig.roarEnvelope(rt)
	local calm = 1 - math.max(windup, roar)
	local phase = t * TAU / Rig.FLAP_PERIOD
	local amp = Rig.flapStrength(t) * calm + 0.25 * roar
	local p = {}
	local function set(name: string, cf: CFrame)
		local i = Rig.boneIndex[name]
		if i then
			p[i] = cf
		end
	end

	-- Gövde: aşağı vuruşta yükselir; ağır ağır sağa sola yalpalar; çığlıkta şahlanır.
	local bob = -0.6 * amp * math.sin(phase) + 0.4 * math.sin(t * 0.5)
	set("govde", CFrame.new(0, bob + windup * 0.8, 0)
		* A(0.03 * math.sin(phase + 1) * amp + windup * 0.15 + roar * 0.08, 0.06 * math.sin(t * 0.23) * calm, 0.05 * math.sin(t * 0.31) * calm))
	set("gogus", A(0.02 * math.sin(phase + 0.5) * amp, 0, 0))

	-- Boyun ve baş: baş gövdenin inip kalkmasına karşı dengede durur, etrafa bakar; çığlıkta
	-- önce geriye kalkar, sonra öne uzanıp gagasını açar.
	local look = math.sin(t * 0.37) * 0.22 + math.sin(t * 0.9) * 0.06
	local nod = math.sin(t * 0.53) * 0.04
	local steady = -0.03 * math.sin(phase + 1) * amp
	set("boyun1", A(steady + windup * 0.12 - roar * 0.1, look * 0.3 * calm, 0))
	set("boyun2", A(steady + nod + windup * 0.1 - roar * 0.12, look * 0.3 * calm, 0))
	set("bas", A(nod - windup * 0.15 + roar * (0.05 + 0.04 * math.sin(t * 9)), look * 0.4 * calm, roar * 0.05 * math.sin(t * 7)))
	set("gaga", A(-(0.04 + roar * (0.5 + 0.06 * math.sin(t * 22))), 0, 0))
	set("tepe", A(-0.08 * math.sin(phase - 1.5) * amp - roar * 0.3 - windup * 0.15, 0.05 * math.sin(t * 1.3), 0))

	-- Kanatlar: kol kanadı kaldırıp indirir, önkol ve el gecikmeyle izler; yukarı vuruşta
	-- el geriye süpürülüp katlanır. Hazırlıkta kanatlar yukarı kalkar, çığlıkta sonuna kadar açılır.
	for side, sgn in { L = 1, R = -1 } do
		local lift = 0.1 + amp * math.sin(phase) + windup * 0.7 - roar * 0.05 + roar * 0.04 * math.sin(t * 13)
		local sweep = 0.3 * amp * math.max(0, math.cos(phase)) * calm
		set("kanatKol" .. side, A(0.06 * math.sin(phase + 0.4) * amp, sgn * 0.1 * math.sin(phase - 0.3) * amp, sgn * lift))
		set("kanatOnkol" .. side, A(0, -sgn * sweep * 0.4, sgn * (-0.35 * amp * math.sin(phase - 0.7) - windup * 0.2)))
		set("kanatEl" .. side, A(0, -sgn * sweep, sgn * (-0.45 * amp * math.sin(phase - 1.1) - windup * 0.25 + roar * 0.1)))
	end

	-- Kuyruk ve kurdeleler: kurdeleler rüzgârda dalgalanan şeritler gibi uca doğru gecikmeli dalgalanır.
	-- Kuyruk kökü gövdenin şahlanmasını dengeler; böylece uzun kurdeleler yere değmez.
	set("kuyruk", A(0.08 * math.sin(phase - 2) * amp - windup * 0.15 - roar * 0.12, 0.05 * math.sin(t * 0.7), 0))
	for k = 1, Rig.STREAMERS do
		for i = 1, 4 do
			local pitch = 0.11 * math.sin(t * 2.0 - i * 0.8 + k * 1.3) + 0.06 * amp * math.sin(phase - i * 0.9) + roar * 0.04 * math.sin(t * 9 - i)
			local yaw = 0.09 * math.sin(t * 1.4 - i * 0.7 + k * 2.1)
			set("kurdele" .. k .. "_" .. i, A(pitch, yaw, 0))
		end
	end

	-- Bacaklar sarkar ve hafifçe sallanır; pençeler ara sıra kapanıp açılır, çığlıkta gerilir.
	local grip = bump(t % 7, 3.0, 4.6, 0.4) * calm
	for side, sgn in { L = 1, R = -1 } do
		set("bacak" .. side, A(0.08 * math.sin(t * 0.9 + sgn) - windup * 0.2 + roar * 0.15, 0, sgn * 0.04 * math.sin(t * 0.7)))
		set("ayak" .. side, A(-0.6 * grip + roar * 0.25, 0, 0))
	end
	return p
end

--- Pozdan, kemiklerin model uzayındaki CFrame'lerini hesaplar. `scale` Model:GetScale().
--- Poz dönüşleri öteleme de içerebilir (gövdenin inip kalkması); öteleme de ölçeklenir.
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
