-- ─────────────────────────────────────────────────────────────────────────────
-- Dokuz kuyruklu tilkinin iskeleti ve animasyon mantığı.
--
-- Bu dosya, build.luau'nun ürettiği veri tablosunun (Rig.bones, Rig.parts, Rig.legs,
-- Rig.tails, Rig.lids, Rig.HALO_AXIS) ALTINA eklenir ve birlikte "TilkiRig"
-- ModuleScript'ini oluşturur. Yalnızca CFrame/Vector3/math kullanır; Roblox servislerine
-- dokunmaz, bu sayede aynı kod Lune ile bilgisayarda da test edilir.
--
-- Gövde, boyun, baş, kulaklar, hale ve dokuz kuyruğun her biri kemiklere bağlıdır. Dört bacak
-- ters kinematikle (IK) çözülür: patiler yere basılı kalır, gövde inip kalkarken dirsekler ve
-- dizler kendiliğinden bükülür. Model -Z yönüne bakar (Roblox'un "ön" yönü).
-- ─────────────────────────────────────────────────────────────────────────────

local TAU = math.pi * 2
local A = CFrame.Angles
local axisAngle = CFrame.fromAxisAngle
local UP = Vector3.new(0, 1, 0)

Rig.ROAR_DURATION = 4.4
Rig.ROAR_INTERVAL = 15
Rig.BREATH_PERIOD = 3.2
Rig.LOOK_PERIOD = 3.4
Rig.BLINK_PERIOD = 5.3
Rig.PAW_PERIOD = 11

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

--- Sayıdan 0..1 arası tekrarlanabilir sözde rastgele sayı.
local function hash(n: number): number
	local x = math.sin(n * 127.1 + 311.7) * 43758.5453
	return x - math.floor(x)
end

--- Uluma başlangıcından bu yana geçen süre `rt` için (hazırlık, uluma) şiddetleri, 0..1.
--- 0.0–1.0 sn hazırlık (hafifçe çömelir, kuyruklarını toplar), 1.0–3.6 sn uluma ve tilki
--- ateşleri, 3.6–4.4 sn sakinleşme.
function Rig.roarEnvelope(rt: number?): (number, number)
	if rt == nil or rt < 0 or rt > Rig.ROAR_DURATION then
		return 0, 0
	end
	local windup = smooth(rt / 1.0) * (1 - smooth((rt - 1.0) / 0.3))
	local roar = smooth((rt - 1.0) / 0.3) * (1 - smooth((rt - 3.6) / 0.8))
	return windup, roar
end

--- Şu an uluma sürüyorsa başlangıcından geçen süreyi, sürmüyorsa nil döner.
--- `now` sunucu saatidir; bu sayede bütün oyuncular ulumayı aynı anda görür.
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

--- Tilki ateşlerinin kuyruk uçlarından çıkıp etrafında dönme oranı (0..1).
function Rig.foxfire(rt: number?): number
	local _, roar = Rig.roarEnvelope(rt)
	return smooth((roar - 0.15) / 0.7)
end

--- Ön patiyi kaldırma: ara sıra bir ön patisini merakla kaldırıp bir süre havada tutar (0..1).
function Rig.pawLift(side: number, t: number, rt: number?): number
	local windup, roar = Rig.roarEnvelope(rt)
	local calm = 1 - math.max(windup, roar)
	local c = t % Rig.PAW_PERIOD
	local a = if side > 0 then 2.0 else 7.5
	return bump(c, a, a + 2.2, 0.45) * calm
end

--- Gövdenin dinlenme yerine göre ötelemesi ve dönüşü: nefes, salınım, çömelme, uluma duruşu.
function Rig.bodyOffset(t: number, rt: number?): (Vector3, number, number, number)
	local windup, roar = Rig.roarEnvelope(rt)
	local calm = 1 - math.max(windup, roar)
	local breath = math.sin(t * TAU / Rig.BREATH_PERIOD)
	local liftL, liftR = Rig.pawLift(1, t, rt), Rig.pawLift(-1, t, rt)
	local offset = Vector3.new(0.18 * (liftR - liftL), 0.07 * breath * calm - 0.55 * windup - 0.2 * roar, 0.25 * windup)
	local pitch = 0.015 * breath * calm - 0.06 * windup + 0.06 * roar
	local yaw = 0.04 * math.sin(t * 0.31) * calm
	local roll = 0.03 * (liftL - liftR) + 0.02 * math.sin(t * 0.43) * calm
	return offset, pitch, yaw, roll
end

local function lookTarget(n: number): (number, number, number)
	if hash(n + 3.1) < 0.3 then
		return 0, -0.05, 0
	end
	return (hash(n) * 2 - 1) * 0.45, (hash(n + 17.3) * 2 - 1) * 0.14, (hash(n + 41.7) * 2 - 1) * 0.28
end

--- Meraklı bakış: baş bir süre bir yöne bakar, sonra yumuşakça yeni bir yöne döner ve yana yatar.
function Rig.headLook(t: number): (number, number, number)
	local n = math.floor(t / Rig.LOOK_PERIOD)
	local b = smooth((t - n * Rig.LOOK_PERIOD) / 0.7)
	local y0, p0, r0 = lookTarget(n - 1)
	local y1, p1, r1 = lookTarget(n)
	return y0 + (y1 - y0) * b, p0 + (p1 - p0) * b, r0 + (r1 - r0) * b
end

--- Göz kırpma: birkaç saniyede bir, bazen iki kez üst üste.
function Rig.blink(t: number): boolean
	local n = math.floor(t / Rig.BLINK_PERIOD)
	local c = t - n * Rig.BLINK_PERIOD
	return c < 0.14 or (hash(n + 7.7) > 0.6 and c > 0.3 and c < 0.42)
end

--- Kulak oynatma: ara sıra bir kulak hızla geriye seğirip yerine döner (0..1).
local function earFlick(side: number, t: number): number
	local period = if side > 0 then 4.3 else 5.9
	local n = math.floor(t / period)
	local c = t - n * period
	if hash(n * 3 + side) < 0.4 then
		return 0
	end
	return bump(c, 1.0, 1.45, 0.12)
end

--- Zaman `t` ve uluma süresi `rt` için kemik dönüşleri (kemik sırası → CFrame).
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

	local offset, pitch, yaw, roll = Rig.bodyOffset(t, rt)
	set("govde", CFrame.new(offset) * A(pitch, yaw, roll))
	set("gogus", A(0.015 * math.sin(t * TAU / Rig.BREATH_PERIOD + 0.6) * calm + 0.03 * roar, 0, 0))
	set("kalca", A(-0.01 * breath * calm, -yaw * 0.5, 0))

	-- Boyun ve baş: meraklı bakış; hazırlıkta başını indirir, ulurken başını gökyüzüne kaldırır.
	local lookYaw, lookPitch, lookRoll = Rig.headLook(t)
	local howlShake = roar * 0.03 * math.sin(t * 11)
	set("boyun", A(calm * lookPitch * 0.4 - windup * 0.15 + roar * 0.45, calm * (lookYaw - yaw) * 0.5, 0))
	set("bas", A(calm * lookPitch * 0.6 - windup * 0.1 + roar * 0.6 + howlShake, calm * lookYaw * 0.5, calm * lookRoll + howlShake))
	-- Çene: negatif X aşağı açar.
	set("cene", A(-(0.01 + roar * (0.55 + 0.05 * math.sin(t * 7)) + windup * 0.02), 0, 0))
	-- Kulaklar: seğirir; hazırlıkta dikleşir, ulurken geriye yatar.
	for side, sgn in { L = 1, R = -1 } do
		local flick = earFlick(sgn, t) * calm
		set("kulak" .. side, A(0.5 * flick - windup * 0.15 + roar * 0.45, 0, sgn * (0.2 * flick + 0.04 * math.sin(t * 0.7 + sgn))))
	end
	-- Hale: başın arkasında yavaşça döner ve süzülür.
	local haloSpin = t * (0.5 + 2.5 * roar)
	set("hale", CFrame.new(0, 0.08 * math.sin(t * 1.3), 0) * axisAngle(Rig.HALO_AXIS, haloSpin))

	-- Dokuz kuyruk: her biri kendi fazında, uca doğru büyüyen dalgalarla salınır. Hazırlıkta
	-- sırtın üstünde toplanır, ulurken yelpaze gibi açılıp titrer.
	for k, tail in Rig.tails do
		for i, bone in tail.bones do
			local w = math.sin(t * 1.05 - i * 0.6 + tail.phase)
			local fan = (0.06 + 0.035 * i) * w * calm
				+ tail.side * (if i == 1 then 1 else 0.35) * (0.22 * roar - 0.12 * windup)
				+ roar * 0.04 * math.sin(t * 9 - i + k)
			local lift = 0.05 * math.sin(t * 0.8 - i * 0.5 + tail.phase * 1.3) * calm
				- (if i == 1 then 1 else 0.3) * (0.15 * windup) + (if i == 1 then 0.08 else 0) * roar
			p[bone] = axisAngle(tail.fan, fan) * axisAngle(tail.lift, lift)
		end
	end
	return p
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

--- -Z'si `look` yönüne bakan, Y'si `upHint`e yakın çerçeve.
function Rig.frame(pos: Vector3, look: Vector3, upHint: Vector3): CFrame
	look = look.Unit
	local right = look:Cross(upHint)
	if right.Magnitude < 1e-4 then
		right = look:Cross(Vector3.new(1, 0, 0))
	end
	right = right.Unit
	return CFrame.fromMatrix(pos, right, right:Cross(look), -look)
end

--- İki parçalı bacak için ters kinematik: kök `hip`, bilek `ankle`, eklemin bükülme yönü `pole`.
--- Üst ve alt parçaların çerçevelerini döner; -Z parça boyunca uzanır.
function Rig.legFrames(hip: Vector3, ankle: Vector3, pole: Vector3, l1: number, l2: number): (CFrame, CFrame)
	local toAnkle = ankle - hip
	local d = math.clamp(toAnkle.Magnitude, math.abs(l1 - l2) + 1e-3, l1 + l2 - 1e-3)
	local u = toAnkle.Unit
	local v = pole - u * pole:Dot(u)
	v = if v.Magnitude > 1e-4 then v.Unit else UP
	local a = (l1 * l1 - l2 * l2 + d * d) / (2 * d)
	local h = math.sqrt(math.max(0, l1 * l1 - a * a))
	local knee = hip + u * a + v * h
	return Rig.frame(hip, knee - hip, v), Rig.frame(knee, hip + u * d - knee, v)
end

--- Bir bacağın bu andaki bölüm çerçeveleri (model uzayında): upper, lower, meta (bilek → pati), foot.
function Rig.solveLeg(leg, boneCFs: { CFrame }, t: number, rt: number?, scale: number)
	local lift = if leg.front then Rig.pawLift(leg.side, t, rt) else 0
	local ball = (leg.ball + Vector3.new(0, 1.6 * lift, -0.5 * lift)) * scale
	local foot = CFrame.new(ball) * A(-0.9 * lift, 0, 0)
	-- kaldırılan ön patide bilek öne doğru kıvrılır
	local ankle = ball + A(-1.1 * lift, 0, 0):VectorToWorldSpace(leg.meta * scale)
	local hip = boneCFs[leg.bone] * (leg.hip * scale)
	local upper, lower = Rig.legFrames(hip, ankle, leg.pole, leg.l1 * scale, leg.l2 * scale)
	return {
		upper = upper,
		lower = lower,
		meta = Rig.frame(ankle, ball - ankle, Vector3.new(0, 0, -1)),
		foot = foot,
	}
end

return Rig
