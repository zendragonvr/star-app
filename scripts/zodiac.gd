# vc184 ZODIAC IN THE SKY (user 2026-11-04). On request only:
# "Star Bridge, show me Taurus" fades in, IN THE REAL SKY, at the real
# position of that constellation right now:
#   - the constellation's figure lines between its real stars (same star
#     IDs and positions as the app's own star map, baked in scripts/zodiac_data.gd);
#   - a glowing line-art emblem of the figure (bull, scorpion, lion ...)
#     drawn around those stars, like a star-atlas picture;
#   - its key stars, brightened and named.
# Everything sits on the sky sphere at 89 m (just inside the stars at 90 m),
# placed by the same astronomy math and Sky Sync yaw as the stars, so it
# stays pinned to the real sky as Earth turns. It is never head-locked and
# never in the room.
# The spoken reading (dates, element, quality, ruling planet, traits) is
# standard Western astrology TRADITION, built in below, and is presented
# as tradition, not science. The emblem art is simulated (drawn in code).
extends Node3D

const AstroMathScript = preload("res://scripts/astro_math.gd")
const R: float = 89.0
const FADE_IN: float = 1.6
const SHOW_SECONDS: float = 60.0

var lat_deg: float = 28.4152
var lon_deg: float = -81.7879
var yaw_offset_deg: float = 0.0
var alt_offset_deg: float = 0.0
var current: String = ""

var _stars: Dictionary = {}        # id -> [ra_h, dec_deg, name, mag]
var _lines: Dictionary = {}        # code -> [[ida, idb], ...]
var _root: Node3D = null
var _line_mat: ShaderMaterial = null
var _art_mat: ShaderMaterial = null
var _alpha: float = 0.0
var _t_shown: float = 0.0
var _segs: Array = []              # [[ra,dec],[ra,dec], kind] kind 0 line, 1 art
var _key_stars: Array = []         # [ra, dec, name, mag]
var _labels: Array = []
var _dots: MultiMeshInstance3D = null
var _line_mesh: MeshInstance3D = null
var _art_mesh: MeshInstance3D = null
var _upd_t: float = 0.0
# Cosmic nebula painting of the emblem (gas + stardust), drawn on the sky.
var _neb_mesh: MeshInstance3D = null
var _neb_mat: ShaderMaterial = null
var _neb_c: Vector2 = Vector2.ZERO    # chart centre of the painting (deg)
var _neb_h: float = 10.0              # half size of the painting (deg)
var _ra0: float = 0.0
var _dec0: float = 0.0
const NEB_GRID: int = 20
const NEB_PX: int = 512
const NEB_SHADER := """
shader_type spatial;
render_mode unshaded, blend_add, cull_disabled, depth_draw_never, depth_test_disabled, fog_disabled;
uniform sampler2D mask : filter_linear_mipmap, repeat_disable;
uniform vec3 c1; uniform vec3 c2; uniform vec3 c3;
uniform float a = 0.0;
uniform float seed = 0.0;
float h21(vec2 p){ p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float vn(vec2 p){ vec2 i = floor(p); vec2 f = fract(p); f = f*f*(3.0-2.0*f);
  return mix(mix(h21(i), h21(i+vec2(1,0)), f.x), mix(h21(i+vec2(0,1)), h21(i+vec2(1,1)), f.x), f.y); }
float fbm(vec2 p){ float v = 0.0; float w = 0.5; for (int k = 0; k < 5; k++){ v += vn(p) * w; p = p * 2.03 + vec2(1.7, 9.2); w *= 0.5; } return v; }
void fragment(){
  vec2 uv = UV;
  float t = TIME * 0.008;
  // Swirl the lookup a little so the gas curls around the figure.
  vec2 q = vec2(fbm(uv * 4.0 + seed + t), fbm(uv * 4.0 - seed + 3.1 - t));
  vec2 wuv = uv + (q - 0.5) * 0.035;
  float core = textureLod(mask, wuv, 1.0).r;
  float body = clamp(textureLod(mask, wuv, 3.5).r * 5.0, 0.0, 1.4);
  float halo = clamp(textureLod(mask, wuv, 5.5).r * 16.0, 0.0, 1.3);
  float far_ = clamp(textureLod(mask, wuv, 7.0).r * 40.0, 0.0, 1.0);
  float fill = textureLod(mask, wuv, 2.5).g;
  float n1 = fbm(uv * 7.0 + q * 2.0 + seed);
  float n2 = fbm(uv * 15.0 - q * 3.0 + seed * 1.7);
  float wisps = smoothstep(0.35, 0.85, n1);
  float gas = body * (0.40 + 1.0 * wisps) + halo * (0.20 + 0.9 * n2 * wisps) + far_ * 0.35 * wisps * n2
            + fill * (0.30 + 0.9 * wisps * n2);
  // Dark dust lanes cut through the glow, like a real nebula.
  float lanes = smoothstep(0.55, 0.75, fbm(uv * 11.0 + q * 4.0 + 7.0));
  gas *= 1.0 - 0.55 * lanes;
  vec3 col = mix(c1, c2, smoothstep(0.25, 0.75, n2 + body * 0.3));
  col = mix(col, c3, clamp(core * 0.6, 0.0, 1.0));
  vec3 e = col * gas + c3 * core * 0.22;
  // Stardust: tiny sparkles thick inside the figure, sparse around it.
  vec2 g = uv * 260.0; vec2 gi = floor(g); vec2 gf = fract(g) - 0.5;
  float r = h21(gi + seed);
  vec2 off = vec2(h21(gi + 3.3), h21(gi + 7.7)) - 0.5;
  float dsz = length(gf - off * 0.6);
  float dens = clamp(body * 0.9 + halo * 0.4, 0.0, 1.0);
  float tw = 0.6 + 0.4 * sin(TIME * (1.0 + r * 3.0) + r * 40.0);
  float spark = step(1.0 - 0.22 * dens, r) * smoothstep(0.16, 0.0, dsz) * tw;
  e += mix(vec3(1.0), c2, 0.3) * spark * 1.2;
  // Soft edge so the painting never shows a border.
  vec2 b = smoothstep(vec2(0.0), vec2(0.22), uv) * smoothstep(vec2(0.0), vec2(0.22), 1.0 - uv);
  float rr = smoothstep(0.75, 0.45, length(uv - 0.5));
  ALBEDO = e * b.x * b.y * rr * a;
}
"""

# ---------------- Astrology tradition (Western, tropical) ----------------
const SIGNS := {
	"Ari": {"sign": "Aries", "con": "Aries, the Ram", "dates": "March 21 to April 19", "element": "Fire", "quality": "Cardinal", "ruler": "Mars",
		"traits": "bold, energetic and a natural leader, quick to start new things, competitive and honest, though sometimes impatient",
		"stars": "Its brightest star is Hamal, an orange giant about 66 light years away, with Sheratan and Mesarthim forming the ram's head.",
		"myth": "In Greek myth it is the golden ram whose fleece Jason sailed to find."},
	"Tau": {"sign": "Taurus", "con": "Taurus, the Bull", "dates": "April 20 to May 20", "element": "Earth", "quality": "Fixed", "ruler": "Venus",
		"traits": "steady, patient and reliable, loyal to the people they love, fond of comfort, good food and beauty, and famously stubborn",
		"stars": "Its red eye is Aldebaran, a giant star 65 light years away. The V of stars around it is the Hyades cluster, the bull's face, and its horns end at Elnath and Tianguan.",
		"myth": "In Greek myth Zeus took the form of a white bull to carry away Europa."},
	"Gem": {"sign": "Gemini", "con": "Gemini, the Twins", "dates": "May 21 to June 20", "element": "Air", "quality": "Mutable", "ruler": "Mercury",
		"traits": "curious, witty and talkative, quick learners who love ideas and people, adaptable, and sometimes restless",
		"stars": "The twins' heads are Castor and Pollux. Pollux is an orange giant 34 light years away; Castor is actually six stars in one system.",
		"myth": "They are the twin brothers Castor and Pollux, inseparable even in death."},
	"Cnc": {"sign": "Cancer", "con": "Cancer, the Crab", "dates": "June 21 to July 22", "element": "Water", "quality": "Cardinal", "ruler": "the Moon",
		"traits": "caring, protective and loyal, deeply emotional and intuitive, home-loving, with a tough shell over a soft heart",
		"stars": "Its stars are faint; at its heart is the Beehive Cluster, hundreds of stars you can see as a fuzzy patch. Tarf is its brightest star.",
		"myth": "In Greek myth it is the crab sent to bite Hercules during his fight with the Hydra."},
	"Leo": {"sign": "Leo", "con": "Leo, the Lion", "dates": "July 23 to August 22", "element": "Fire", "quality": "Fixed", "ruler": "the Sun",
		"traits": "warm, confident and generous, born to shine, creative and playful, with a big loyal heart and a love of attention",
		"stars": "Its heart is Regulus, a blue-white star 79 light years away. The backwards question mark is the lion's mane, and Denebola is the tip of its tail.",
		"myth": "It is the Nemean lion, defeated by Hercules in his first labour."},
	"Vir": {"sign": "Virgo", "con": "Virgo, the Maiden", "dates": "August 23 to September 22", "element": "Earth", "quality": "Mutable", "ruler": "Mercury",
		"traits": "thoughtful, practical and hard working, with a sharp eye for detail, kind and helpful, sometimes a perfectionist",
		"stars": "Its brightest star is Spica, a hot blue pair of stars 250 light years away, the ear of wheat in the maiden's hand.",
		"myth": "She is often linked to Demeter or her daughter Persephone, goddesses of the harvest."},
	"Lib": {"sign": "Libra", "con": "Libra, the Scales", "dates": "September 23 to October 22", "element": "Air", "quality": "Cardinal", "ruler": "Venus",
		"traits": "fair, charming and diplomatic, peace makers who love balance, beauty and harmony, though they can find choosing hard",
		"stars": "Its two brightest stars have the longest names in the sky: Zubenelgenubi and Zubeneschamali, the southern and northern claws.",
		"myth": "Its stars were once the scorpion's claws; the Romans made them the scales of justice."},
	"Sco": {"sign": "Scorpio", "con": "Scorpius, the Scorpion", "dates": "October 23 to November 21", "element": "Water", "quality": "Fixed", "ruler": "Mars and Pluto",
		"traits": "passionate, intense and determined, deeply loyal, brave and private, with powerful intuition",
		"stars": "Its red heart is Antares, a supergiant so big it would swallow Mars's orbit, 550 light years away. The curled tail ends at Shaula, the stinger.",
		"myth": "In Greek myth the scorpion killed the hunter Orion, so the two are never in the sky at the same time."},
	"Sgr": {"sign": "Sagittarius", "con": "Sagittarius, the Archer", "dates": "November 22 to December 21", "element": "Fire", "quality": "Mutable", "ruler": "Jupiter",
		"traits": "adventurous, optimistic and free spirited, funny and honest, always looking for the next journey or big idea",
		"stars": "Its brightest stars make the Teapot. Kaus Australis and Nunki lead the way, and it points toward the centre of our galaxy.",
		"myth": "It is a centaur archer, often said to be Chiron, aiming his arrow at the scorpion's heart."},
	"Cap": {"sign": "Capricorn", "con": "Capricornus, the Sea Goat", "dates": "December 22 to January 19", "element": "Earth", "quality": "Cardinal", "ruler": "Saturn",
		"traits": "ambitious, disciplined and patient, responsible and wise beyond their years, with a dry sense of humour",
		"stars": "Its brightest star is Deneb Algedi, the tail of the goat, and Dabih and Algedi mark its horns.",
		"myth": "The god Pan leapt into a river to escape a monster, and became half goat, half fish."},
	"Aqr": {"sign": "Aquarius", "con": "Aquarius, the Water Bearer", "dates": "January 20 to February 18", "element": "Air", "quality": "Fixed", "ruler": "Saturn and Uranus",
		"traits": "original, independent and inventive, humanitarian thinkers who love freedom, friendship and new ideas",
		"stars": "Its brightest stars are Sadalsuud and Sadalmelik, both yellow supergiants, and the water jar is a small Y of stars.",
		"myth": "He is Ganymede, the cup bearer of the gods, pouring water from his jar."},
	"Psc": {"sign": "Pisces", "con": "Pisces, the Fishes", "dates": "February 19 to March 20", "element": "Water", "quality": "Mutable", "ruler": "Jupiter and Neptune",
		"traits": "gentle, compassionate and imaginative, dreamy and artistic, deeply empathetic and wise",
		"stars": "Its stars are faint. Alrescha, the knot, ties the cords of two fish, and the western fish is a ring of stars called the Circlet.",
		"myth": "Aphrodite and her son Eros turned into fish and tied themselves together to escape the monster Typhon."},
	"Oph": {"sign": "Ophiuchus", "con": "Ophiuchus, the Serpent Bearer", "dates": "the Sun is really in it from about November 29 to December 17", "element": "", "quality": "", "ruler": "",
		"traits": "it is not one of the twelve traditional signs, but the Sun really does pass through it every year, which is why people call it the thirteenth sign",
		"stars": "Its brightest star is Rasalhague, the head of the serpent bearer.",
		"myth": "He is Asclepius, the healer, holding a great serpent."},
}

# vc185 DETAILED READINGS (user: "I need more detailed horoscopes").
# Standard Western astrology tradition for each sign: symbol, polarity,
# natural house, body area, birthstone, colour, lucky day and number,
# key phrase, strengths, challenges, love style, best matches, work.
# Spoken after the stars and myth, always framed as tradition.
const DETAIL := {
	"Ari": {"symbol": "the Ram", "phrase": "I am", "house": "first", "polarity": "masculine, outgoing", "body": "the head and face", "stone": "diamond", "color": "red", "day": "Tuesday", "number": "nine",
		"strengths": "courage, enthusiasm, honesty and a fearless drive to be first", "challenges": "impatience, a quick temper and starting more things than they finish",
		"love": "In love, Aries is passionate and direct, loves the chase and needs a partner who can keep up", "matches": "Leo, Sagittarius, Gemini and Aquarius",
		"work": "They shine as leaders, entrepreneurs, athletes, firefighters and anyone who starts new projects"},
	"Tau": {"symbol": "the Bull", "phrase": "I have", "house": "second", "polarity": "feminine, inward", "body": "the throat and neck", "stone": "emerald", "color": "green and soft pink", "day": "Friday", "number": "six",
		"strengths": "patience, loyalty, practical good sense and a calm that steadies everyone around them", "challenges": "stubbornness, possessiveness and resisting change",
		"love": "In love, Taurus is devoted, affectionate and sensual, slow to commit but loyal for life", "matches": "Virgo, Capricorn, Cancer and Pisces",
		"work": "They thrive in finance, cooking, design, music, gardening and building things that last"},
	"Gem": {"symbol": "the Twins", "phrase": "I think", "house": "third", "polarity": "masculine, outgoing", "body": "the hands, arms and lungs", "stone": "pearl and agate", "color": "yellow", "day": "Wednesday", "number": "five",
		"strengths": "wit, curiosity, quick learning and a gift for talking with anyone", "challenges": "restlessness, indecision and getting bored fast",
		"love": "In love, Gemini needs fun, conversation and a partner who is also a best friend", "matches": "Libra, Aquarius, Aries and Leo",
		"work": "They do well in writing, teaching, media, sales, tech and anything with lots of variety"},
	"Cnc": {"symbol": "the Crab", "phrase": "I feel", "house": "fourth", "polarity": "feminine, inward", "body": "the chest and stomach", "stone": "ruby and moonstone", "color": "silver and white", "day": "Monday", "number": "two",
		"strengths": "deep care, loyalty, strong intuition and a fierce protectiveness of family", "challenges": "moodiness, holding on to the past and hiding hurt inside their shell",
		"love": "In love, Cancer is nurturing, romantic and loyal, and wants a safe, close home together", "matches": "Scorpio, Pisces, Taurus and Virgo",
		"work": "They are great in caring work: nursing, teaching, cooking, counselling, and running a home or business like family"},
	"Leo": {"symbol": "the Lion", "phrase": "I will", "house": "fifth", "polarity": "masculine, outgoing", "body": "the heart and spine", "stone": "peridot", "color": "gold and orange", "day": "Sunday", "number": "one",
		"strengths": "confidence, generosity, warmth and natural star power", "challenges": "pride, stubbornness and needing to be noticed",
		"love": "In love, Leo is loyal, playful and generous, and loves big romantic gestures", "matches": "Aries, Sagittarius, Gemini and Libra",
		"work": "They shine on stage and in leadership: acting, performing, management, teaching and creative arts"},
	"Vir": {"symbol": "the Maiden", "phrase": "I analyse", "house": "sixth", "polarity": "feminine, inward", "body": "the digestive system", "stone": "sapphire", "color": "navy and earthy browns", "day": "Wednesday", "number": "five",
		"strengths": "attention to detail, reliability, kindness and a love of helping", "challenges": "worry, perfectionism and being too hard on themselves",
		"love": "In love, Virgo shows care through small thoughtful acts and wants a partner they can trust completely", "matches": "Taurus, Capricorn, Cancer and Scorpio",
		"work": "They excel in health, science, research, editing, organising and any job that needs precision"},
	"Lib": {"symbol": "the Scales", "phrase": "I balance", "house": "seventh", "polarity": "masculine, outgoing", "body": "the lower back and kidneys", "stone": "opal", "color": "pastel blue and pink", "day": "Friday", "number": "six",
		"strengths": "fairness, charm, diplomacy and a great eye for beauty", "challenges": "indecision, avoiding conflict and trying too hard to please",
		"love": "In love, Libra is romantic and attentive, and is happiest in a true partnership of equals", "matches": "Gemini, Aquarius, Leo and Sagittarius",
		"work": "They do well in law, design, fashion, diplomacy, art and anything about bringing people together"},
	"Sco": {"symbol": "the Scorpion", "phrase": "I desire", "house": "eighth", "polarity": "feminine, inward", "body": "the pelvic area", "stone": "topaz", "color": "deep red and black", "day": "Tuesday", "number": "eight",
		"strengths": "passion, loyalty, bravery and the focus to see things through", "challenges": "jealousy, secrecy and finding it hard to forgive",
		"love": "In love, Scorpio is intense and all in, wanting deep trust and real closeness", "matches": "Cancer, Pisces, Virgo and Capricorn",
		"work": "They are drawn to investigation, medicine, psychology, research and any work that digs beneath the surface"},
	"Sgr": {"symbol": "the Archer", "phrase": "I see", "house": "ninth", "polarity": "masculine, outgoing", "body": "the hips and thighs", "stone": "turquoise", "color": "purple", "day": "Thursday", "number": "three",
		"strengths": "optimism, honesty, humour and a big appetite for adventure", "challenges": "impatience, bluntness and a fear of being tied down",
		"love": "In love, Sagittarius needs freedom, laughter and a partner to explore the world with", "matches": "Aries, Leo, Libra and Aquarius",
		"work": "They love travel, teaching, publishing, outdoor work, philosophy and sharing big ideas"},
	"Cap": {"symbol": "the Sea Goat", "phrase": "I use", "house": "tenth", "polarity": "feminine, inward", "body": "the knees, bones and teeth", "stone": "garnet", "color": "brown and dark grey", "day": "Saturday", "number": "eight",
		"strengths": "discipline, ambition, patience and a strong sense of responsibility", "challenges": "working too hard, pessimism and holding feelings back",
		"love": "In love, Capricorn takes its time, but is loyal, protective and in it for the long run", "matches": "Taurus, Virgo, Scorpio and Pisces",
		"work": "They rise high in business, engineering, government, finance and any long-term climb to the top"},
	"Aqr": {"symbol": "the Water Bearer", "phrase": "I know", "house": "eleventh", "polarity": "masculine, outgoing", "body": "the ankles and circulation", "stone": "amethyst", "color": "electric blue", "day": "Saturday", "number": "four",
		"strengths": "originality, independence, big-picture thinking and caring about the world", "challenges": "seeming distant, stubborn opinions and needing lots of space",
		"love": "In love, Aquarius wants a best friend first, with freedom, honesty and shared ideals", "matches": "Gemini, Libra, Aries and Sagittarius",
		"work": "They are natural inventors, scientists, tech builders, activists and space explorers"},
	"Psc": {"symbol": "the Fishes", "phrase": "I believe", "house": "twelfth", "polarity": "feminine, inward", "body": "the feet", "stone": "aquamarine", "color": "sea green", "day": "Thursday", "number": "seven",
		"strengths": "compassion, imagination, creativity and deep intuition", "challenges": "escaping into daydreams, being too trusting and taking on others' sadness",
		"love": "In love, Pisces is gentle, romantic and devoted, and loves with their whole heart", "matches": "Cancer, Scorpio, Taurus and Capricorn",
		"work": "They flourish in music, art, film, healing, spiritual work and helping others"},
}

const NAME_TO_CODE := {
	"aries": "Ari", "taurus": "Tau", "tarus": "Tau", "torus": "Tau", "toros": "Tau",
	"gemini": "Gem", "cancer": "Cnc", "leo": "Leo", "virgo": "Vir", "libra": "Lib", "lebra": "Lib",
	"scorpio": "Sco", "scorpius": "Sco", "sagittarius": "Sgr", "sagitarius": "Sgr", "capricorn": "Cap",
	"capricornus": "Cap", "aquarius": "Aqr", "pisces": "Psc", "ophiuchus": "Oph",
}

# ---------------- Emblem line art ----------------
# Chart coordinates in degrees around each constellation's centre: x to the
# WEST (right on a star chart, north up), y north. Drawn around the real
# star layout (see the vc184 notes), so the stars sit inside the picture.
# A "tube" is a body/limb outline generated around a centre line.
func _art(code: String) -> Array:
	var p: Array = []
	match code:
		"Tau":
			p.append([[0.8, 0.2], [-1.5, -1.2], [-5.2, 0.8], [-5.8, 3.2], [-3.6, 6.0], [-0.8, 5.6], [0.8, 2.8], [0.8, 0.2]])
			p.append([[-3.6, 6.0], [-6.5, 9.2], [-10.5, 12.8], [-15.8, 15.5], [-12.0, 11.2], [-7.6, 7.8], [-5.0, 5.4]])
			p.append([[-5.8, 3.2], [-9.8, 5.4], [-14.5, 7.2], [-19.3, 7.9], [-14.6, 5.8], [-9.6, 3.6], [-5.6, 2.0]])
			p.append([[-0.8, 5.6], [3.0, 8.2], [8.0, 9.2], [13.0, 7.8], [16.5, 3.0], [15.5, -2.0]])
			p.append([[0.8, 2.8], [2.6, 0.0], [4.6, -2.6]])
			p.append([[4.6, -2.6], [3.6, -8.6], [3.0, -11.6], [4.8, -11.9], [5.6, -8.4], [6.6, -3.2]])
			p.append([[8.6, -3.4], [10.6, -9.8], [10.8, -14.4], [12.6, -14.6], [12.6, -9.6], [11.8, -3.6]])
			p.append([[6.6, -3.2], [8.6, -3.4]])
			p.append([[11.8, -3.6], [13.5, -5.3], [15.5, -2.0]])
		"Sco":
			p.append_array(_tube([[11.0, 10.5], [6.3, 7.9], [4.3, 7.2], [2.8, 5.4], [-0.3, -0.7], [-0.6, -4.4], [-1.1, -8.8], [-4.3, -9.8], [-9.1, -10.1], [-11.5, -7.5], [-10.6, -6.2], [-9.4, -4.6]], 1.9, 0.5))
			p.append([[11.5, 11.8], [13.4, 14.6], [16.5, 16.4], [18.6, 15.4], [16.4, 14.6], [14.6, 12.2], [12.4, 10.6]])
			p.append([[12.4, 9.4], [15.4, 8.6], [18.6, 7.4], [19.4, 5.6], [17.4, 6.2], [14.6, 7.0], [12.0, 8.6]])
			p.append([[-9.4, -4.6], [-7.6, -2.6], [-6.8, -3.4], [-8.4, -4.8]])
			for k in range(4):
				var bx: float = 6.0 - float(k) * 1.6
				var by: float = 7.6 - float(k) * 1.4
				p.append([[bx, by + 1.0], [bx + 2.2, by + 3.2], [bx + 3.0, by + 2.6]])
				p.append([[bx - 0.6, by - 1.2], [bx + 1.2, by - 3.6], [bx + 2.2, by - 3.6]])
		"Leo":
			p.append(_circle(8.6, 4.3, 4.3, 22))
			p.append([[12.9, 3.0], [14.0, 2.4], [13.6, 0.8], [12.2, 1.2]])
			p.append([[6.4, 8.4], [1.0, 6.4], [-5.0, 4.0], [-9.8, 2.6], [-15.0, -0.6], [-17.4, -2.4]])
			p.append([[-17.4, -2.4], [-20.6, -1.2], [-22.6, 1.6], [-21.8, 3.6], [-20.4, 2.4]])
			p.append([[5.8, -0.2], [6.2, -6.2], [-3.0, -6.6], [-11.0, -5.6], [-15.6, -3.6]])
			p.append([[7.2, -6.0], [7.6, -12.2], [9.0, -12.4], [8.6, -6.4]])
			p.append([[4.6, -6.4], [4.2, -12.0], [5.6, -12.2], [5.8, -6.4]])
			p.append([[-10.2, -5.6], [-11.2, -12.0], [-9.8, -12.2], [-8.8, -5.8]])
			p.append([[-13.2, -4.4], [-14.8, -11.6], [-13.4, -11.8], [-12.0, -4.8]])
		"Ari":
			p.append([[1.4, 2.0], [4.6, 1.6], [5.8, -1.4], [4.2, -4.2], [1.6, -2.8], [0.2, -0.2], [1.4, 2.0]])
			var sp: Array = []
			for k in range(30):
				var a: float = float(k) / 29.0 * TAU * 1.25
				var rr: float = 2.6 - float(k) / 29.0 * 2.0
				sp.append([2.0 + cos(a + 1.2) * rr, 2.4 + sin(a + 1.2) * rr])
			p.append(sp)
			p.append([[0.6, 2.4], [-4.0, 4.6], [-9.0, 6.0], [-12.2, 4.2], [-12.8, 0.2]])
			p.append([[-0.4, -2.0], [-5.0, -3.0], [-11.0, -2.6], [-12.8, 0.2]])
			for lx in [-2.0, -4.2, -9.0, -11.0]:
				p.append([[lx, -2.6], [lx - 0.3, -8.2], [lx + 0.8, -8.4]])
		"Gem":
			p.append(_circle(-7.0, 10.4, 1.4, 14))
			p.append(_circle(-9.8, 6.6, 1.4, 14))
			p.append_array(_tube([[-6.6, 9.0], [-1.9, 7.2], [4.2, 2.1], [9.1, -0.3], [11.1, -0.2]], 1.3, 0.7))
			p.append_array(_tube([[-9.4, 5.2], [-4.1, -1.1], [-0.4, -2.6], [5.9, -6.7], [8.0, -7.4]], 1.3, 0.7))
			p.append([[-4.4, 8.0], [-7.4, 4.4]])
			p.append([[-2.2, 6.4], [0.4, 9.8]])
			p.append([[-5.8, 1.2], [-3.8, -6.6]])
		"Cnc":
			p.append(_ellipse(-0.6, 1.6, 3.2, 2.4, 20))
			p.append([[-1.0, 4.0], [-1.6, 8.0], [-1.1, 11.0], [0.6, 12.2], [-0.4, 10.4], [-2.6, 11.6]])
			p.append([[-3.0, -0.2], [-3.6, -3.6], [-4.1, -6.0], [-5.8, -6.8], [-4.6, -5.2], [-5.6, -3.4]])
			for k in range(3):
				var ly: float = 0.6 + float(k) * 1.4
				p.append([[2.4, ly], [5.0, ly - 3.0 - float(k) * 1.6], [6.3, -8.7 + float(k) * 2.6]])
				p.append([[-3.6, ly + 0.4], [-6.4, ly + 1.2], [-7.6, ly - 0.6]])
		"Vir":
			p.append(_circle(24.0, 4.6, 1.8, 16))
			p.append([[22.4, 3.2], [14.4, 0.8], [8.7, 0.2], [5.6, 1.8]])
			p.append([[22.4, 1.2], [14.4, -1.6], [8.7, -2.6], [5.6, -3.4]])
			p.append([[16.0, 1.6], [12.0, 7.0], [6.0, 11.6], [3.5, 11.5], [5.0, 6.0], [8.0, 1.0]])
			p.append([[5.6, 1.8], [-4.6, 1.2], [-11.5, 3.0], [-23.7, 3.2]])
			p.append([[5.6, -3.4], [-4.0, -4.8], [-15.3, -6.8], [-22.8, -6.8]])
			p.append([[-23.7, 3.2], [-22.8, -6.8]])
			p.append([[8.7, -2.0], [3.0, -6.2], [-2.2, -10.9]])
			for k in range(4):
				p.append([[-2.2 + float(k) * 0.4, -10.9 + float(k) * 0.4], [-3.4 + float(k) * 0.4, -10.0 + float(k) * 0.4]])
		"Lib":
			p.append([[1.0, 12.4], [1.0, -1.0]])
			p.append([[-1.6, -1.0], [3.6, -1.0]])
			p.append([[7.6, 7.2], [1.0, 8.0], [-4.2, 8.6]])
			p.append([[7.6, 7.2], [5.2, 4.0], [10.0, 4.0], [7.6, 7.2]])
			p.append(_arc(7.6, 4.0, 2.4, PI, TAU, 10))
			p.append([[-4.2, 8.6], [-6.6, 5.2], [-1.8, 5.2], [-4.2, 8.6]])
			p.append(_arc(-4.2, 5.2, 2.4, PI, TAU, 10))
		"Sgr":
			p.append(_arc(5.4, -2.4, 6.0, -0.9, 0.9, 14))
			p.append([[8.4, 2.2], [4.6, -2.4], [8.4, -7.0]])
			p.append([[1.0, -2.0], [12.7, -3.4], [15.6, -3.2]])
			p.append([[15.6, -3.2], [14.0, -2.0], [14.2, -4.4], [15.6, -3.2]])
			p.append(_circle(-1.0, 8.6, 1.6, 14))
			p.append_array(_tube([[-1.0, 7.0], [1.0, 2.6], [1.4, -1.6]], 1.6, 1.4))
			p.append([[1.4, -1.6], [-2.0, -3.6], [-8.0, -3.0], [-11.8, 1.0], [-14.0, -2.4]])
			p.append([[-2.0, -3.6], [-3.4, -10.0], [-3.9, -13.1], [-3.5, -17.2]])
			p.append([[0.6, -3.0], [0.6, -10.0], [1.4, -13.4]])
			p.append([[-8.0, -3.0], [-10.0, -10.0], [-10.0, -15.1]])
			p.append([[-10.6, -1.2], [-12.6, -8.2], [-11.6, -12.4]])
		"Cap":
			p.append([[9.6, 4.6], [-1.3, 2.4], [-11.3, 2.6]])
			p.append([[4.0, -6.0], [-6.0, -4.4], [-11.3, 2.6]])
			p.append(_circle(10.6, 4.4, 1.8, 14))
			p.append([[10.2, 6.0], [10.6, 9.6], [8.6, 12.0], [9.8, 9.0], [9.4, 6.2]])
			p.append([[9.0, 3.0], [4.0, -6.0]])
			p.append([[6.0, -2.0], [6.8, -8.8], [8.2, -9.2]])
			p.append([[4.4, -4.6], [4.6, -10.0], [5.8, -10.4]])
			p.append([[-11.3, 2.6], [-14.4, 5.6], [-13.4, 2.4], [-15.0, -0.8], [-11.3, 2.6]])
		"Aqr":
			p.append(_circle(6.0, 11.8, 1.5, 14))
			p.append_array(_tube([[6.0, 10.2], [8.0, 4.6], [10.0, -1.0]], 1.8, 1.4))
			p.append([[10.0, -1.0], [12.6, -6.0], [13.6, -7.0]])
			p.append([[9.0, -1.0], [7.0, -6.4], [8.0, -7.4]])
			p.append([[6.6, 8.8], [2.6, 9.0], [0.2, 8.6]])
			p.append([[1.6, 10.4], [-3.8, 11.0], [-4.6, 7.0], [-1.0, 5.6], [1.6, 10.4]])
			var wv: Array = []
			for k in range(24):
				var f: float = float(k) / 23.0
				var bx: float = lerp(-2.6, -19.6, f)
				var by: float = lerp(6.0, -11.2, f) + sin(f * 18.0) * 0.8
				wv.append([bx, by])
			p.append(wv)
		"Psc":
			p.append(_ellipse(17.4, -5.4, 4.8, 2.4, 20))
			p.append([[22.2, -5.4], [24.8, -3.0], [24.8, -7.8], [22.2, -5.4]])
			p.append(_ellipse(-8.8, 17.6, 1.9, 4.2, 20))
			p.append([[-8.8, 21.8], [-7.0, 24.2], [-10.6, 24.2], [-8.8, 21.8]])
			p.append([[12.6, -5.2], [9.7, -2.7], [-2.7, -2.0], [-6.2, -1.7], [-13.2, -3.3], [-17.1, -0.1], [-22.1, -6.7]])
			p.append([[-22.1, -6.7], [-16.2, -3.9], [-13.2, 6.1], [-8.0, 11.8], [-8.8, 13.4]])
		"Oph":
			p.append(_circle(-9.8, 25.0, 1.8, 16))
			p.append([[0.1, 19.4], [-11.8, 14.2]])
			p.append([[-11.8, 14.2], [-15.4, -0.8], [-5.6, -16.2]])
			p.append([[0.1, 19.4], [5.2, -1.3], [7.7, -14.7]])
			p.append([[-5.0, 4.0], [-6.8, -21.7]])
			var sn: Array = []
			for k in range(28):
				var f2: float = float(k) / 27.0
				sn.append([lerp(22.0, -24.0, f2), 5.0 + sin(f2 * 9.0) * 2.4 - f2 * 2.0])
			p.append(sn)
	return p

static func _circle(cx: float, cy: float, r: float, n: int) -> Array:
	var out: Array = []
	for k in range(n + 1):
		var a: float = TAU * float(k) / float(n)
		out.append([cx + cos(a) * r, cy + sin(a) * r])
	return out

static func _ellipse(cx: float, cy: float, rx: float, ry: float, n: int) -> Array:
	var out: Array = []
	for k in range(n + 1):
		var a: float = TAU * float(k) / float(n)
		out.append([cx + cos(a) * rx, cy + sin(a) * ry])
	return out

static func _arc(cx: float, cy: float, r: float, a0: float, a1: float, n: int) -> Array:
	var out: Array = []
	for k in range(n + 1):
		var a: float = lerp(a0, a1, float(k) / float(n))
		out.append([cx + cos(a) * r, cy + sin(a) * r])
	return out

static func _tube(c: Array, w0: float, w1: float) -> Array:
	# Two outline sides + end caps around a centre line, width tapering w0 -> w1.
	var left: Array = []
	var right: Array = []
	for i in range(c.size()):
		var a: Vector2 = Vector2(c[max(i - 1, 0)][0], c[max(i - 1, 0)][1])
		var b: Vector2 = Vector2(c[min(i + 1, c.size() - 1)][0], c[min(i + 1, c.size() - 1)][1])
		var d: Vector2 = (b - a).normalized()
		var n: Vector2 = Vector2(-d.y, d.x)
		var w: float = lerp(w0, w1, float(i) / float(max(c.size() - 1, 1))) * 0.5
		var pt := Vector2(c[i][0], c[i][1])
		left.append([pt.x + n.x * w, pt.y + n.y * w])
		right.append([pt.x - n.x * w, pt.y - n.y * w])
	var out: Array = [left, right]
	out.append([left[0], right[0]])
	out.append([left[left.size() - 1], right[right.size() - 1]])
	return out

# ---------------- data ----------------
func _ready() -> void:
	_load_data()
	_root = Node3D.new()
	_root.top_level = true
	add_child(_root)
	_line_mat = _glow_mat(Color(0.80, 0.90, 1.0), 1.0)
	_art_mat = _glow_mat(Color(1.0, 0.86, 0.62), 0.22)
	visible = false

func _load_data() -> void:
	# Baked star data (scripts/zodiac_data.gd), generated from the app's own
	# star map files, so nothing depends on reading CSVs inside the APK.
	var D = load("res://scripts/zodiac_data.gd")
	_stars = D.STARS.duplicate()
	_lines = D.LINES.duplicate()

func code_for(text: String) -> String:
	var low: String = " " + text.to_lower() + " "
	for k in NAME_TO_CODE.keys():
		if low.contains(" " + k + " ") or low.contains(" " + k + ",") or low.contains(" " + k + ".") or low.contains(" " + k + "?"):
			return NAME_TO_CODE[k]
	return ""

# ---------------- show / hide ----------------
func show_sign(code: String) -> String:
	if not _lines.has(code) or not SIGNS.has(code):
		return ""
	current = code
	_build(code)
	_alpha = 0.0
	_t_shown = 0.0
	visible = true
	_update_positions()
	return _speech(code)

func hide_sign() -> void:
	_t_shown = SHOW_SECONDS  # fades out in _process

func _speech(code: String) -> String:
	var s: Dictionary = SIGNS[code]
	var up: bool = _centre_alt(code) > 0.0
	var where: String = "It is up in your sky right now." if up else "It is below your horizon right now, so look down to see where it is under the ground."
	var t: String = "This is " + str(s["con"]) + ". " + where + " " + str(s["stars"]) + " " + str(s["myth"]) + " "
	if code == "Oph":
		t += "Ophiuchus is the thirteenth constellation of the zodiac: " + str(s["traits"]) + "."
	else:
		var el: String = str(s["element"]).to_lower()
		var art: String = "an" if el.begins_with("a") or el.begins_with("e") else "a"
		var d: Dictionary = DETAIL[code]
		var sg: String = str(s["sign"])
		t += "Now the horoscope side, in astrology tradition. " + sg + " is for people born from " + str(s["dates"]) + ". Its symbol is " + str(d["symbol"]) + ", and its key phrase is " + str(d["phrase"]) + ". "
		t += "It is " + art + " " + el + " sign, " + str(s["quality"]).to_lower() + ", " + str(d["polarity"]) + ", ruled by " + str(s["ruler"]) + ", and it rules the " + str(d["house"]) + " house. "
		t += "People born under " + sg + " are said to be " + str(s["traits"]) + ". "
		t += "Their strengths are " + str(d["strengths"]) + ". Their challenges are " + str(d["challenges"]) + ". "
		t += str(d["love"]) + ". Best matches are " + str(d["matches"]) + ". "
		t += str(d["work"]) + ". "
		t += sg + " is linked to " + str(d["body"]) + ". Its birthstone is " + str(d["stone"]) + ", its colour " + str(d["color"]) + ", its lucky day " + str(d["day"]) + ", and its lucky number " + str(d["number"]) + "."
	return t

func _centre_alt(code: String) -> float:
	var v := Vector3.ZERO
	for pr in _lines[code]:
		for id in pr:
			if _stars.has(id):
				v += _dir(_stars[id][0], _stars[id][1])
	return rad_to_deg(asin(clamp(v.normalized().y, -1.0, 1.0)))

func _dir(ra_h: float, dec_deg: float) -> Vector3:
	var j: Dictionary = AstroMathScript.jds_from_unix(Time.get_unix_time_from_system())
	return AstroMathScript.star_world_dir(ra_h, dec_deg, j["tt"], j["ut1"], lat_deg, lon_deg, yaw_offset_deg, alt_offset_deg)

func _build(code: String) -> void:
	for c in _root.get_children():
		c.queue_free()
	_labels.clear()
	_segs.clear()
	_key_stars.clear()
	# Centre of the constellation, for the chart coordinates of the art.
	var ids: Dictionary = {}
	for pr in _lines[code]:
		ids[pr[0]] = true
		ids[pr[1]] = true
	var cv := Vector3.ZERO
	for id in ids.keys():
		if _stars.has(id):
			cv += AstroMathScript.unit_from_radec(_stars[id][0], _stars[id][1])
	cv = cv.normalized()
	var ra0: float = atan2(cv.y, cv.x)
	var dec0: float = asin(cv.z)
	# Figure lines between real stars.
	for pr in _lines[code]:
		if _stars.has(pr[0]) and _stars.has(pr[1]):
			_segs.append([[_stars[pr[0]][0], _stars[pr[0]][1]], [_stars[pr[1]][0], _stars[pr[1]][1]], 0])
	# Emblem art: chart (x west, y north, degrees) -> RA/Dec (inverse gnomonic).
	for poly in _art(code):
		for i in range(poly.size() - 1):
			_segs.append([_chart_to_radec(poly[i], ra0, dec0), _chart_to_radec(poly[i + 1], ra0, dec0), 1])
	_ra0 = ra0
	_dec0 = dec0
	_build_nebula(code)
	# Key stars: the 4 brightest in the figure, named.
	var lst: Array = []
	for id in ids.keys():
		if _stars.has(id):
			lst.append(_stars[id])
	lst.sort_custom(func(a, b): return a[3] < b[3])
	for i in range(min(4, lst.size())):
		_key_stars.append(lst[i])
	_line_mesh = MeshInstance3D.new()
	_line_mesh.material_override = _line_mat
	_root.add_child(_line_mesh)
	_art_mesh = MeshInstance3D.new()
	_art_mesh.material_override = _art_mat
	_root.add_child(_art_mesh)
	# Bright dots on the key stars.
	_dots = MultiMeshInstance3D.new()
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var q := QuadMesh.new()
	q.size = Vector2(1.0, 1.0)
	mm.mesh = q
	mm.instance_count = _key_stars.size()
	_dots.multimesh = mm
	_dots.material_override = _dot_mat()
	_root.add_child(_dots)
	for ks in _key_stars:
		var lb := Label3D.new()
		lb.text = str(ks[2])
		lb.font_size = 48
		lb.pixel_size = 0.03
		lb.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		lb.modulate = Color(0.85, 0.93, 1.0, 0.0)
		lb.outline_size = 6
		lb.outline_modulate = Color(0, 0, 0, 0.0)
		lb.no_depth_test = true
		_root.add_child(lb)
		_labels.append(lb)

static func _chart_to_radec(pt: Array, ra0: float, dec0: float) -> Array:
	var xi: float = -deg_to_rad(float(pt[0]))   # chart x is west; RA grows east
	var eta: float = deg_to_rad(float(pt[1]))
	var rho: float = sqrt(xi * xi + eta * eta)
	var c: float = atan(rho)
	var dec: float = dec0
	var ra: float = ra0
	if rho > 0.0:
		dec = asin(cos(c) * sin(dec0) + eta * sin(c) * cos(dec0) / rho)
		ra = ra0 + atan2(xi * sin(c), rho * cos(dec0) * cos(c) - eta * sin(dec0) * sin(c))
	return [fposmod(rad_to_deg(ra) / 15.0, 24.0), rad_to_deg(dec)]

func _update_positions() -> void:
	if current == "" or _line_mesh == null:
		return
	var j: Dictionary = AstroMathScript.jds_from_unix(Time.get_unix_time_from_system())
	var st0 := SurfaceTool.new()
	st0.begin(Mesh.PRIMITIVE_TRIANGLES)
	var st1 := SurfaceTool.new()
	st1.begin(Mesh.PRIMITIVE_TRIANGLES)
	for sg in _segs:
		var a: Vector3 = AstroMathScript.star_world_dir(sg[0][0], sg[0][1], j["tt"], j["ut1"], lat_deg, lon_deg, yaw_offset_deg, alt_offset_deg) * R
		var b: Vector3 = AstroMathScript.star_world_dir(sg[1][0], sg[1][1], j["tt"], j["ut1"], lat_deg, lon_deg, yaw_offset_deg, alt_offset_deg) * R
		var w: float = 0.42 if int(sg[2]) == 0 else 0.30      # ~0.27 / 0.19 deg wide at 89 m: bold enough to read across the sky
		_ribbon(st0 if int(sg[2]) == 0 else st1, a, b, w)
	_line_mesh.mesh = st0.commit()
	_art_mesh.mesh = st1.commit()
	_update_nebula(j)
	for i in range(_key_stars.size()):
		var ks: Array = _key_stars[i]
		var d: Vector3 = AstroMathScript.star_world_dir(ks[0], ks[1], j["tt"], j["ut1"], lat_deg, lon_deg, yaw_offset_deg, alt_offset_deg)
		var size: float = clamp(2.4 - float(ks[3]) * 0.35, 0.9, 2.6)
		_dots.multimesh.set_instance_transform(i, Transform3D(Basis().scaled(Vector3(size, size, size)), d * (R - 0.5)))
		(_labels[i] as Label3D).global_position = d * (R - 1.0) + Vector3(0.0, -1.8, 0.0)

func _ribbon(st: SurfaceTool, a: Vector3, b: Vector3, w: float) -> void:
	# Flat ribbon lying on the sky sphere (normal = outward), so it looks like
	# a glowing line painted on the sky from where you stand.
	var d: Vector3 = (b - a)
	if d.length() < 0.001:
		return
	var out: Vector3 = ((a + b) * 0.5).normalized()
	var side: Vector3 = d.cross(out).normalized() * (w * 0.5)
	for p in [a - side, a + side, b + side, a - side, b + side, b - side]:
		st.add_vertex(p)

func _glow_mat(col: Color, a: float) -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = Shader.new()
	m.shader.code = "shader_type spatial; render_mode unshaded, blend_add, cull_disabled, depth_draw_never, depth_test_disabled, fog_disabled; uniform vec3 col; uniform float a = 1.0; void fragment(){ ALBEDO = col * a; }"
	m.set_shader_parameter("col", Vector3(col.r, col.g, col.b))
	m.set_shader_parameter("a", 0.0)
	m.set_meta("peak", a)
	return m

func _dot_mat() -> ShaderMaterial:
	var m := ShaderMaterial.new()
	m.shader = Shader.new()
	m.shader.code = "shader_type spatial; render_mode unshaded, blend_add, cull_disabled, depth_draw_never, depth_test_disabled, fog_disabled; uniform float a = 1.0; void vertex(){ MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]); MODELVIEW_MATRIX = MODELVIEW_MATRIX * mat4(vec4(length(MODEL_MATRIX[0].xyz),0,0,0), vec4(0,length(MODEL_MATRIX[1].xyz),0,0), vec4(0,0,length(MODEL_MATRIX[2].xyz),0), vec4(0,0,0,1)); } void fragment(){ float d = length(UV - 0.5) * 2.0; float g = pow(clamp(1.0 - d, 0.0, 1.0), 2.2); ALBEDO = vec3(1.0, 0.95, 0.85) * g * 1.4 * a; }"
	m.set_shader_parameter("a", 0.0)
	return m

func _process(delta: float) -> void:
	if not visible:
		return
	_t_shown += delta
	var target: float = 1.0 if _t_shown < SHOW_SECONDS else 0.0
	_alpha = move_toward(_alpha, target, delta / FADE_IN)
	if _alpha <= 0.0 and target == 0.0:
		visible = false
		current = ""
		return
	# Gentle shimmer on the emblem so it feels alive, not pasted on.
	var shimmer: float = 0.9 + 0.1 * sin(Time.get_ticks_msec() * 0.0015)
	_line_mat.set_shader_parameter("a", float(_line_mat.get_meta("peak")) * _alpha)
	_art_mat.set_shader_parameter("a", float(_art_mat.get_meta("peak")) * _alpha * shimmer)
	if _neb_mat != null:
		_neb_mat.set_shader_parameter("a", 0.85 * _alpha)
	if _dots != null:
		(_dots.material_override as ShaderMaterial).set_shader_parameter("a", _alpha)
	for lb in _labels:
		(lb as Label3D).modulate.a = _alpha
		(lb as Label3D).outline_modulate.a = _alpha
	_upd_t += delta
	if _upd_t >= 1.0:   # the sky turns slowly; re-place once a second
		_upd_t = 0.0
		_update_positions()

# ---------------- cosmic nebula painting ----------------
func _palette(code: String) -> Array:
	# Colours follow the sign's element: fire, earth, air, water.
	var el: String = str(SIGNS[code]["element"])
	match el:
		"Fire":
			return [Vector3(0.85, 0.10, 0.32), Vector3(1.0, 0.48, 0.12), Vector3(1.0, 0.90, 0.70)]
		"Earth":
			return [Vector3(0.05, 0.55, 0.42), Vector3(0.95, 0.72, 0.28), Vector3(0.95, 1.0, 0.85)]
		"Air":
			return [Vector3(0.45, 0.22, 1.0), Vector3(0.15, 0.78, 1.0), Vector3(0.90, 0.95, 1.0)]
		"Water":
			return [Vector3(0.10, 0.28, 1.0), Vector3(0.78, 0.22, 0.95), Vector3(0.85, 0.92, 1.0)]
	return [Vector3(0.10, 0.65, 0.70), Vector3(0.62, 0.25, 0.95), Vector3(0.90, 1.0, 0.95)]

func _build_nebula(code: String) -> void:
	var polys: Array = _art(code)
	if polys.is_empty():
		_neb_mesh = null
		_neb_mat = null
		return
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for poly in polys:
		for pt in poly:
			lo = Vector2(min(lo.x, float(pt[0])), min(lo.y, float(pt[1])))
			hi = Vector2(max(hi.x, float(pt[0])), max(hi.y, float(pt[1])))
	_neb_c = (lo + hi) * 0.5
	_neb_h = max(hi.x - lo.x, hi.y - lo.y) * 0.5 * 1.3 + 1.5
	# Paint the emblem strokes into a mask; the shader blurs it with mipmaps
	# into soft gas at several sizes.
	var img := Image.create(NEB_PX, NEB_PX, false, Image.FORMAT_RG8)
	img.fill(Color(0, 0, 0))
	var rad: int = 5
	for poly in polys:
		for i in range(poly.size() - 1):
			var pa: Vector2 = _neb_px(poly[i])
			var pb: Vector2 = _neb_px(poly[i + 1])
			var steps: int = int(ceil(pa.distance_to(pb))) + 1
			for k in range(steps + 1):
				var p: Vector2 = pa.lerp(pb, float(k) / float(steps))
				var cx: int = int(p.x)
				var cy: int = int(p.y)
				for dy in range(-rad, rad + 1):
					var yy: int = cy + dy
					if yy < 0 or yy >= NEB_PX:
						continue
					for dx in range(-rad, rad + 1):
						var xx: int = cx + dx
						if xx < 0 or xx >= NEB_PX:
							continue
						var v: float = clamp(1.0 - sqrt(float(dx * dx + dy * dy)) / float(rad + 1), 0.0, 1.0)
						var old: Color = img.get_pixel(xx, yy)
						if v > old.r:
							img.set_pixel(xx, yy, Color(v, old.g, 0))
	# Fill the inside of closed shapes (heads, bodies) so the gas is a solid
	# painted figure, not only an outline. Scanline, even-odd.
	for poly in polys:
		if poly.size() < 4:
			continue
		var pts: Array = []
		for pt in poly:
			pts.append(_neb_px(pt))
		if (pts[0] as Vector2).distance_to(pts[pts.size() - 1]) > 3.0:
			continue
		var ymin: int = NEB_PX
		var ymax: int = 0
		for q in pts:
			ymin = min(ymin, int(q.y))
			ymax = max(ymax, int(q.y))
		for yy in range(max(ymin, 0), min(ymax + 1, NEB_PX)):
			var fy: float = float(yy) + 0.5
			var xs: Array = []
			for i in range(pts.size() - 1):
				var p0: Vector2 = pts[i]
				var p1: Vector2 = pts[i + 1]
				if (p0.y <= fy and p1.y > fy) or (p1.y <= fy and p0.y > fy):
					xs.append(p0.x + (fy - p0.y) / (p1.y - p0.y) * (p1.x - p0.x))
			xs.sort()
			for k in range(0, xs.size() - 1, 2):
				for xx in range(max(int(xs[k]), 0), min(int(xs[k + 1]) + 1, NEB_PX)):
					var old2: Color = img.get_pixel(xx, yy)
					img.set_pixel(xx, yy, Color(old2.r, 0.8, 0))
	img.generate_mipmaps()
	_neb_mat = ShaderMaterial.new()
	_neb_mat.shader = Shader.new()
	_neb_mat.shader.code = NEB_SHADER
	_neb_mat.set_shader_parameter("mask", ImageTexture.create_from_image(img))
	var pal: Array = _palette(code)
	_neb_mat.set_shader_parameter("c1", pal[0])
	_neb_mat.set_shader_parameter("c2", pal[1])
	_neb_mat.set_shader_parameter("c3", pal[2])
	_neb_mat.set_shader_parameter("seed", float(code.hash() % 97) * 0.37)
	_neb_mat.set_shader_parameter("a", 0.0)
	_neb_mesh = MeshInstance3D.new()
	_neb_mesh.material_override = _neb_mat
	_neb_mesh.sorting_offset = -1.0
	_root.add_child(_neb_mesh)

func _neb_px(pt: Array) -> Vector2:
	# Chart degrees -> mask pixels. Image x runs with chart x; image y runs south
	# (row 0 = north), matching the UVs of the sky grid below.
	var u: float = (float(pt[0]) - _neb_c.x) / (2.0 * _neb_h) + 0.5
	var v: float = 0.5 - (float(pt[1]) - _neb_c.y) / (2.0 * _neb_h)
	return Vector2(u, v) * float(NEB_PX)

func _update_nebula(j: Dictionary) -> void:
	# A curved grid lying on the sky sphere, using the same chart->sky mapping
	# as the emblem lines, so the painting sits exactly over the real stars.
	if _neb_mesh == null:
		return
	var n: int = NEB_GRID
	var pos: Array = []
	for iy in range(n + 1):
		for ix in range(n + 1):
			var u: float = float(ix) / float(n)
			var v: float = float(iy) / float(n)
			var cx: float = _neb_c.x + (u - 0.5) * 2.0 * _neb_h
			var cy: float = _neb_c.y - (v - 0.5) * 2.0 * _neb_h
			var rd: Array = _chart_to_radec([cx, cy], _ra0, _dec0)
			pos.append(AstroMathScript.star_world_dir(rd[0], rd[1], j["tt"], j["ut1"], lat_deg, lon_deg, yaw_offset_deg, alt_offset_deg) * (R + 1.0))
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for iy in range(n):
		for ix in range(n):
			var i0: int = iy * (n + 1) + ix
			var quad: Array = [[i0, ix, iy], [i0 + 1, ix + 1, iy], [i0 + n + 2, ix + 1, iy + 1], [i0, ix, iy], [i0 + n + 2, ix + 1, iy + 1], [i0 + n + 1, ix, iy + 1]]
			for qv in quad:
				st.set_uv(Vector2(float(qv[1]) / float(n), float(qv[2]) / float(n)))
				st.add_vertex(pos[qv[0]])
	_neb_mesh.mesh = st.commit()
