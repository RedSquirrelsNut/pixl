

precision mediump float;

uniform float time;
uniform vec2 resolution;

uniform float camera_fov;
uniform vec3 camera_position;
uniform vec3 camera_rotation;

uniform float waterLevel;

uniform float cloudDensity1;
uniform float cloudDensity2;

uniform float sunHeight;

uniform float terrainSeed;

uniform bool normalsMode;

#define NEAR 0.0
#define FAR 1000.0
#define EPSILON 0.001
#define MAX_STEPS 100
#define PI 3.1415926538

float shininess = 1000000.0;

vec2 add = vec2(1.0, 0.0);
#define HASHSCALE1 .1031

//  1 out, 2 in...
float Hash12(vec2 p) {
    vec3 p3 = fract(vec3(p.xyx) * HASHSCALE1);
    p3 += dot(p3, p3.yzx + 19.19 + terrainSeed);
    return fract((p3.x + p3.y) * p3.z);
}

float Noise(in vec2 x) {
    vec2 p = floor(x);
    vec2 f = fract(x); 
    f = f * f * (3.0 - 2.0 * f);

    float res = mix(mix(Hash12(p), Hash12(p + add.xy), f.x), mix(Hash12(p + add.yx), Hash12(p + add.xx), f.x), f.y);
    return res;
}

//--------------------------------------------------------------------------
float FractalNoise(in vec2 xy) {
    float w = .7;
    float f = 0.0;

    for(int i = 0; i < 4; i++) {
        f += Noise(xy) * w;
        w *= 0.5;
        xy *= 2.7;
    }
    return f;
}

// Rotation matrix around the X axis.
mat3 rotateX(float theta) {
    float c = cos(theta);
    float s = sin(theta);
    return mat3(vec3(1, 0, 0), vec3(0, c, -s), vec3(0, s, c));
}

// Rotation matrix around the Y axis.
mat3 rotateY(float theta) {
    float c = cos(theta);
    float s = sin(theta);
    return mat3(vec3(c, 0, s), vec3(0, 1, 0), vec3(-s, 0, c));
}

// Rotation matrix around the Z axis.
mat3 rotateZ(float theta) {
    float c = cos(theta);
    float s = sin(theta);
    return mat3(vec3(c, -s, 0), vec3(s, c, 0), vec3(0, 0, 1));
}

// Identity matrix.
mat3 identity() {
    return mat3(vec3(1, 0, 0), vec3(0, 1, 0), vec3(0, 0, 1));
}

struct Surface {
    float sd;
    vec3 color;
    bool lit;
    float shine;
};

Surface sdSphere(vec3 point, vec3 position, float radius, vec3 col, bool lit, float shine) {
    vec3 distanceVector = point - position;

    return Surface(length(distanceVector) - radius, col, lit, shine);
}


Surface sdFloor(vec3 p, vec3 col, bool lit, float shine) {
    float d = p.y + 1.;
    return Surface(d, col, lit,shine);
}

Surface sdBox(vec3 p, vec3 b, vec3 offset, vec3 col, bool lit, float shine, mat3 transform) {
    p = (p - offset) * transform;
    vec3 q = abs(p) - b;
    float d = length(max(q, 0.0)) + min(max(q.x, max(q.y, q.z)), 0.0);
    return Surface(d, col, lit,shine);
}

Surface sdCappedCylinder(vec3 p, float h, float r, vec3 col, bool lit, float shine) {
    vec2 d = abs(vec2(length(p.xz), p.y)) - vec2(h, r);
    float sd = min(max(d.x, d.y), 0.0) + length(max(d, 0.0));
    return Surface(sd, col, lit,shine);
}

Surface minWithColor(Surface obj1, Surface obj2) {
    if(obj2.sd < obj1.sd)
        return obj2;
    return obj1;
}

//Add a way to control blending
Surface opSmoothUnion(Surface obj1, Surface obj2, float k) {
    float h = clamp(0.5 + 0.5 * (obj2.sd - obj1.sd) / k, 0.0, 1.0);
    //Cool result if you switch objs
    float nsd = mix(obj2.sd, obj1.sd, h) - k * h * (1.0 - h);
    vec3 nc = mix(obj2.color, obj1.color, h);
    float ns = mix(obj2.shine, obj1.shine, h);
    bool lit = obj1.lit && obj2.lit;
    return Surface(nsd, nc, lit,ns);
}

Surface opSmoothSubtraction( Surface d1, Surface d2, float k ) {
    float h = clamp( 0.5 - 0.5*(d2.sd+d1.sd)/k, 0.0, 1.0 );
    float nsd =  mix( d2.sd, -d1.sd, h ) + k*h*(1.0-h);
    vec3 nc = mix(d2.color, d1.color, h);
    float ns = mix(d2.shine, d1.shine, h);
    bool lit = d1.lit && d2.lit;
    return Surface(nsd, nc, lit, ns);
}

Surface opRound(Surface obj, float rad) {
    return Surface(obj.sd - rad, obj.color, obj.lit, obj.shine);
}

float displace(vec3 p) {
    return sin(1.6 * p.x) * sin(1.6 * p.y) * sin(1.6 * p.z);
}

float displace2(vec3 p) {
    float x = max(sin(1.2 * p.x), -0.7);
    float y = sin(0.8 * p.y);
    float z = max(sin(1.2 * p.z), -0.7);

    float o = x * y * z;
    return o;
}

float displace3(vec3 p) {
    return sin(0.6 * p.x) * sin(0.6 * p.y) * sin(0.6 * p.z);
}

float displace4(vec3 p) {
    float w = (Noise(p.xz * 0.05 * .5) * 0.75 + .15);
    return 40.0*w*w;
}

float displace5(vec3 p) {
    return sin(0.1 * p.x * time) * sin(0.1 * p.y * time) * sin(0.1 * p.z * time);
}

Surface opDisplace(Surface primitive, vec3 p, int f) {
    float d1 = primitive.sd;
    float d2;
    if(f == 0) {
        d2 = displace(p);
    } else if(f == 1) {
        d2 = displace2(p);
    } else {
        d2 = displace5(p);
    }
    return Surface(d1 + d2, primitive.color, primitive.lit,primitive.shine);
}

vec3 opInfRep(in vec3 p, in vec3 c) {
    vec3 q = mod(p + 0.5 * c, c) - 0.5 * c;
    return q;
}

vec3 opRepLim( in vec3 p, in float c, in vec3 l)
{
    vec3 q = p-c*clamp(floor(p/c+0.5),-l,l);
    return q;
}

const mat2 rotate2D = mat2(1.3623, 1.7531, -1.7131, 1.4623);

vec3 color_brick(in vec3 p) {
    const vec3 brickColor = vec3(0.2);
    const vec3 mortarColor = vec3(0.8);

    const vec2 brickSize = vec2(1.3,1.15);
    const vec2 brickPct = vec2(0.9,0.85);

    vec2 position = p.zy/brickSize;
    vec2 useBrick = vec2(0);

    if(fract(position.y*0.5) > 0.5)
        position.x += 0.5;
    position = fract(position);
    useBrick = step(position,brickPct);

    vec3 color = mix(mortarColor, brickColor, useBrick.x*useBrick.y);

    position = p.xy/brickSize;
    if(fract(position.y*0.5) > 0.5)
        position.x += 0.5;
    position = fract(position);
    useBrick = step(position,brickPct);

    color = (color+mix(mortarColor, brickColor, useBrick.x*useBrick.y))/2.0;

    return color;
}

Surface sceneSDF(vec3 p) {
    bool displace = true;
    bool displaceMax = false;
    vec3 purple = vec3(1.0, 0.258, 0.258);
    vec3 green = vec3(0.22, max(Noise(p.xz) * .6 + .25,0.7), 0.22);
    vec3 purple2 = vec3(1.0, 0.0, 0.0);
    // //vec3 pillarColor = mix(purple,mix(mix(purple, purple2, sin(time) * cos(time)), mix(checkBoardTex * sin(p.z*time), checkBoardTex2 * rotateY(p.x*time*2.0),sin(time)),sin(p.y*time)),0.3);
    vec3 pillarColor = mix(purple2, purple, abs(sin(p.z * time) * sin(p.x * time)));
    float surface_shine = shininess;

    float effect =  0.0;
    float w = (Noise((p.xz) * 0.05 * .25) * 0.75 + .15);
    effect = 66.0*w*w;//(sin(p.x*-0.2)*p.x*0.04) + (sin(p.z*-0.2)*p.z*0.04);
    effect += 40.0*w*w;
    float beachLevel = 47.0;
    float beachMod = sin(p.y)-Noise(p.zx * 0.9 * .55);
    beachLevel = beachLevel-beachMod;
    if(effect > beachLevel) {
         float h = clamp(0.5 + 0.5 * (effect - beachLevel) / 2., 0.0, 1.0);
        green = mix(green,mix(vec3(0.760, 0.698, 0.501),clamp(vec3(Noise(p.zx)),0.1,1.),0.2),h);
    }
    //TODO: second noise creates more realistic waves, takes 5-10fps off on this pc...
    float water = -waterLevel-(Noise(p.zx * 0.9 * .25+time)*Noise(p.xz * 0.9 * .25-time));
    if(effect > water) {
        effect = water;
        green = vec3(0., 0.458 * Noise(p.zx * 0.05 * .25 +time), max(0.466 * Noise(p.zx * 0.05 * .25+time),0.6));
        surface_shine = 10.;
    }

    vec3 floorP = p + vec3(0.0, -0.5 + effect, 0.0);

    Surface co = sdFloor(floorP, green, true,surface_shine);
    vec3 spread = vec3(60.0, 0.0, 60.0);

    Surface co2 = sdCappedCylinder(p, 5.0, 50.0, pillarColor, true, surface_shine);
    co2 = opDisplace(co2, p, 2);

    return opSmoothUnion(co, co2, 0.5);// return minWithColor(co,co3);
}

Surface rayMarch(vec3 rayOrigin, vec3 rayDirection, float start, float end) {
    float depth = start;
    Surface co; //Closest obj

    for(int i = 0; i < MAX_STEPS; i++) {
        vec3 point = rayOrigin + depth * rayDirection;
        co = sceneSDF(point);
        depth += co.sd;
        if(abs(co.sd) < EPSILON || co.sd > end)
            break;
    }
    co.sd = depth;
    return co;//1.0 - (float(steps) / float(MAX_STEPS));
}

vec3 estimateNormal(vec3 p) {
    return normalize(vec3(sceneSDF(vec3(p.x + EPSILON, p.y, p.z)).sd - sceneSDF(vec3(p.x - EPSILON, p.y, p.z)).sd, sceneSDF(vec3(p.x, p.y + EPSILON, p.z)).sd - sceneSDF(vec3(p.x, p.y - EPSILON, p.z)).sd, sceneSDF(vec3(p.x, p.y, p.z + EPSILON)).sd - sceneSDF(vec3(p.x, p.y, p.z - EPSILON)).sd));
}

vec3 phongContribForLight(vec3 k_d, vec3 k_s, float alpha, vec3 p, vec3 eye, vec3 lightPos, vec3 lightIntensity) {
    vec3 N = estimateNormal(p);
    vec3 L = normalize(lightPos - p);
    vec3 V = normalize(eye - p);
    vec3 R = normalize(reflect(-L, N));

    float dotLN = clamp(dot(L, N), 0., 1.);
    float dotRV = dot(R, V);

    if(dotLN < 0.0) {
            // Light not visible from this point on the surface
        return vec3(0.0, 0.0, 0.0);
    }

    if(dotRV < 0.0) {
            // Light reflection in opposite direction as viewer, apply only diffuse
            // component
        return lightIntensity * (k_d * dotLN);
    }
    return lightIntensity * (k_d * dotLN + k_s * pow(dotRV, alpha));
}

vec3 phongIllumination(vec3 k_a, vec3 k_d, vec3 k_s, float alpha, vec3 p, vec3 eye) {
    const vec3 ambientLight = 0.5 * vec3(1.0, 1.0, 1.0);
    vec3 color = ambientLight * k_a;

    vec3 light2Pos = vec3(-305, 100, -305);
                          //Second vec is light color
    vec3 light2Intensity = vec3(0.9, 0.9, 0.9);

    color += phongContribForLight(k_d, k_s, alpha, p, eye, light2Pos, light2Intensity);
    return color;
}

mat4 lookAtViewMatrix(vec3 eye, vec3 center, vec3 up) {
    vec3 f = normalize(center - eye);
    vec3 s = normalize(cross(f, up));
    vec3 u = cross(s, f);
    return mat4(vec4(s, 0.0), vec4(u, 0.0), vec4(-f, 0.0), vec4(0.0, 0.0, 0.0, 1.0));
}

mat3 get_camera_direction(float roll, float pitch, float yaw) {
    float cr = cos(roll);
    float cp = cos(pitch);
    float cy = cos(yaw);
    float sr = sin(roll);
    float sp = sin(pitch);
    float sy = sin(yaw);

    //TODO: MAD operations
    mat3 mat = mat3(vec3(cy * cp, cy * sp * sr - sy * cr, cy * sp * cr + sy * sr), vec3(sy * cp, sy * sp * sr + cy * cr, sy * sp * cr - cy * sr), vec3(-sp, cp * sr, cp * cr));

    return mat;
}

vec3 rayDirection(float fieldOfView, vec2 size, vec2 fragCoord) {
    vec2 xy = fragCoord - size / 2.0;
    float z = size.y / tan(radians(fieldOfView) / 2.0);

    return normalize(vec3(xy, -z));
}

vec3 sunLight = normalize(vec3(0.0, 1., 0.0 ));
// vec3 sunColour = vec3(0.99, 0.66, 0.47);
vec3 sunColour = vec3(0.96, 0.72, 0.55);
vec3 moonColour = vec3(1);

//--------------------------------------------------------------------------
// Simply Perlin clouds that fade to the horizon...
// 200 units above the ground...
vec3 GetClouds(in vec3 sky, in vec3 rp, in vec3 rd) {
    //float cloudDensity = 5.;
    //THIS CLOUD CODE IS GOOD, COULD PROBS BE MORE SPARSE THO.
    if(rd.y < 0.01)
        return sky;
    float v = (200.0 - rp.y) / rd.y;
    vec2 sky_start = vec2(1.,1.);
    rd.xz *= v;
    rd.xz += rp.xz;// * time;
    rd.xz *= .010;
    rd.xz += time * 0.25;
    float f = 0.;
    if (cloudDensity1 != 0.) {
        f = (FractalNoise(rd.xz) - (1.-cloudDensity1)) * cloudDensity2;
    }
    // Uses the ray's y component for horizon fade of fixed colour clouds...
    sky = mix(sky, vec3(.55, .55, .52), clamp(f * rd.y - .1, 0.0, 1.0));

    return sky;
}

//--------------------------------------------------------------------------
// Grab all sky information for a given ray from camera
vec3 GetSky(in vec3 rd) {
    float sunAmount = max(dot(rd, sunLight * rotateX(sunHeight)), 0.0);
    // float moonAmount = -sunAmount;
    float v = pow(1.0 - max(rd.y, 0.0), 5.) * .5;

    vec3 day_sky = vec3(v * sunColour.x * 0.4 + 0.18, v * sunColour.y * 0.4 + 0.22, v * sunColour.z * 0.4 + .4);// * sunAmount;
	// vec3 night_sky = vec3(0.037, 0.068, 0.260);
    vec3 sky = day_sky;
    // if(sunAmount == 0.) {
    //     sky = night_sky;
    // }
    // vec3 sky = mix(day_sky,night_sky,1.-(sunAmount)); 
    // Wide glare effect...
    sky = sky + sunColour * pow(sunAmount, 22.5) * .32;
	// Actual sun...
    sky = sky + sunColour * min(pow(sunAmount, 1150.0), .3) * .65;

    return sky;
}


// Merge mountains into the sky background for correct disappearance...
vec3 ApplyFog(in vec3 rgb, in float dis, in vec3 dir) {
    float fogAmount = exp(-dis * 0.0000035);
    return mix(GetSky(dir), rgb, fogAmount);
}

vec3 PostEffects(vec3 rgb) {
	//#define CONTRAST 1.1
	//#define SATURATION 1.12
	//#define BRIGHTNESS 1.3
	//rgb = pow(abs(rgb), vec3(0.45));
	//rgb = mix(vec3(.5), mix(vec3(dot(vec3(.2125, .7154, .0721), rgb*BRIGHTNESS)), rgb*BRIGHTNESS, SATURATION), CONTRAST);
    rgb = (1.0 - exp(-rgb * 6.0)) * 1.0024;
	//rgb = clamp(rgb+hash12(fragCoord.xy*rgb.r)*0.1, 0.0, 1.0);
    return rgb;
}

void main() {
    vec3 directionOfRay = rayDirection(camera_fov, resolution.xy, gl_FragCoord.xy);
    // directionOfRay *= rotateY(-time / 1.1);
    directionOfRay *= get_camera_direction(camera_rotation.y,camera_rotation.x,camera_rotation.z);//rotateY(camera_rotation.x); //* rotateX(camera_rotation.y);
    vec3 cam_pos = camera_position;// * rotateX(time);
    // cam_pos *= rotateY(time / 1.2);

    Surface co = rayMarch(cam_pos, directionOfRay, NEAR, FAR);
    // cam_pos.y = co.y;

    if(co.sd > FAR - EPSILON) {
        vec3 sky = GetSky(directionOfRay);
        sky = GetClouds(sky, cam_pos, directionOfRay);
        gl_FragColor = vec4(sky, 1.0);
        return;
    }

    vec3 p = cam_pos + co.sd * directionOfRay;

    vec3 K_a = vec3(0.4, 0.4, 0.4);//ambient
    vec3 K_d = co.color;//diffuse
    vec3 K_s = vec3(0.4, 0.4, 0.4);//spec
    
    vec3 color = vec3(0.0, 0.0, 0.0);
    if(!normalsMode) {
    if(co.lit) {
        color = phongIllumination(K_a, K_d, K_s, co.shine, p, cam_pos);
    } else {
        color = K_d;
    }
    } else {
        color = estimateNormal(p);
    }
    // color = ApplyFog(color, co.sd * co.sd, directionOfRay);
    // color = PostEffects(color);
    gl_FragColor = vec4(color, 1.0);
}