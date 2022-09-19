/*
    Draw game to seperate canvas then stretch the
    image onto a 2d canvas, we can also draw the text/blur
    on that canvas as well, should be faster.
    https://developer.mozilla.org/en-US/docs/Web/API/CanvasRenderingContext2D/filter

    blur at the very least should be done via a canvas2d... or a shader
*/

var mesh, timer, shaderProgram;
var gStats;
var container, focus_text, cam_pos_text, cam_rot_text, tick_text, cloud_text, sun_text, waterLevel_text;

var hideUI = true;

const mouse = [3.9499999999999957, 9.71445146547012e-17];

var useNormalsMode = false;

var mouseSensitivity = 30;

var cloudSlider1;
var cloudSlider2;
var cloudDensity2 = 5.;
var cloudDensity1 = 0.55;

var sunSlider;
var sunHeight = 1.45;

var waterLevelSlider;
var waterLevel = -60.;

var paused = false,
    pause_text;

var delta = 0.;

var terrainSeed = 0;

var game_text;
/*
Pos: -24,3,-29
Rot: 3.9499999999999957,9.71445146547012e-17,0
*/
var camera_rot = [3.9499999999999957, 9.71445146547012e-17, 0];
var camera_pos = [-24, 3, -29];
var camera_fov = 90.;

var tree_spread_xy = [get_random(100), get_random(100)];
var tree_spread_seeds = [get_random(100), get_random(100), get_random(100)];

function get_random(max) {
    return Math.random() * max;
}

function degrees_to_radians(degrees) {
    var pi = Math.PI;
    return degrees * (pi / 180);
}

function smoothstep(min, max, value) {
    var x = Math.max(0, Math.min(1, (value - min) / (max - min)));
    return x * x * (3 - 2 * x);
}

// start() is the main function that gets called first by index.html
var start = function() {
    container = document.getElementById("webgl-container");
    gStats = new Stats();
    gStats.domElement.style.position = 'absolute';
    gStats.domElement.style.top = '0px';
    container.append(gStats.domElement);

    focus_text = document.createElement("div");
    focus_text.id = "blink_me";
    focus_text.innerHTML = "Click to focus.";
    container.appendChild(focus_text);

    pause_text = document.createElement("div");
    pause_text.id = "blink_me";
    pause_text.innerHTML = "Paused";
    container.appendChild(pause_text);

    game_text = document.createElement("div");
    game_text.id = "game_text";
    game_text.innerHTML = "Pixlz Demo";
    container.appendChild(game_text);

    tick_text = document.createElement("div");
    tick_text.id = "tick_text";
    tick_text.innerHTML = "Ticks: ";
    container.appendChild(tick_text);

    delta_text = document.createElement("div");
    delta_text.id = "delta_text";
    delta_text.innerHTML = "Delta: ";
    container.appendChild(delta_text);

    cam_pos_text = document.createElement("div");
    cam_pos_text.id = "cam_pos_text";
    cam_pos_text.innerHTML = "Camera Pos: []";
    container.appendChild(cam_pos_text);

    cam_rot_text = document.createElement("div");
    cam_rot_text.id = "cam_rot_text";
    cam_rot_text.innerHTML = "Camera Rot: []";
    container.appendChild(cam_rot_text);

    waterLevel_text = document.createElement("div");
    waterLevel_text.id = "waterLevel_text";
    waterLevel_text.innerHTML = "Water Level: ";
    container.appendChild(waterLevel_text);

    waterLevelSlider = document.getElementById("waterLevelRange");
    waterLevelSlider.value = waterLevel;

    sun_text = document.createElement("div");
    sun_text.id = "sun_text";
    sun_text.innerHTML = "Sun: ";
    container.appendChild(sun_text);


    cloud_text = document.createElement("div");
    cloud_text.id = "cloud_text";
    cloud_text.innerHTML = "Clouds:";
    container.appendChild(cloud_text);

    cloudSlider1 = document.getElementById("cloudDensityRange1");
    cloudSlider1.value = cloudDensity1;

    cloudSlider2 = document.getElementById("cloudDensityRange2");
    cloudSlider2.value = cloudDensity2;

    sunSlider = document.getElementById("sunHeightRange");
    sunSlider.value = sunHeight;

    // Initialize the WebGL 2.0 canvas
    initCanvas();
    // Create timer that will be used for fragment shader
    timer = new Timer();

    shaderProgram = new Shader('vertShader', 'fragShader');
    // Activate the shader program
    shaderProgram.UseProgram();

    // Set vertices of the mesh to be the canonical screen space
    var vertices = [-1.0, -1.0,
        1.0, 1.0, -1.0, 1.0,
        1.0, -1.0
    ];

    // Set indices for the vertices above
    var indices = [2, 0, 1,
        1, 0, 3
    ];

    // Create a mesh based upon the defined vertices and indices
    mesh = new Mesh(vertices, indices, shaderProgram);

    // Render the scene
    drawScene();
};

// starts the canvas and gl
var initCanvas = function() {
    //this is the game surface
    canvas = document.getElementById('game-surface');

    //pointer lock for all browsers
    canvas.requestPointerLock = canvas.requestPointerLock ||
        canvas.mozRequestPointerLock;

    document.exitPointerLock = document.exitPointerLock ||
        document.mozExitPointerLock;

    canvas.onclick = function() {
        canvas.requestPointerLock();
    };
    // Hook pointer lock state change events
    document.addEventListener('pointerlockchange', changeCallback, false);
    document.addEventListener('mozpointerlockchange', changeCallback, false);
    document.addEventListener('webkitpointerlockchange', changeCallback, false);

    // Hook mouse move events
    //document.addEventListener("mousemove", onDocumentMouseMove, false);
    // const sb = document.querySelector('#framework')
    // btn.onclick = (event) => {
    //     event.preventDefault();
    //     // show the selected index
    //     alert(sb.selectedIndex);
    // };
    var speed = 1.0;

    //document.addEventListener('mousemove', onDocumentMouseMove);

    document.addEventListener("keydown", (event) => {
        if (event.getModifierState("Shift")) {
            console.log(speed);
            speed = 100.0;
        } else {
            speed = 50.0;
        }
        //TODO: ADD ADJUSTABLE ZOOM & FOV, SMOOTH STEPPING IT WOULD BE FUN AS WELL
        if (event.code === "ControlLeft") {
            camera_fov = 20.;
        }
    });

    document.addEventListener("keyup", (event) => {
        if (event.code === "ControlLeft") {
            camera_fov = 90.;
        }
    });
    document.addEventListener("keydown", (event) => {
        // event.preventDefault();
        // var delta = timer.GetDelta(); //timer.GetTimeInMillis();
        // console.log(delta);
        //console.log(timer.GetTimeInMillis());
        if (event.code === "KeyM") {
            var max = 1000;
            var r = Math.floor(Math.random() * (max + 1));
            terrainSeed = r;
        }
        if (event.code === "KeyP") {
            console.log(camera_pos);
        }
        if (event.code === "Escape") {
            paused = !paused;
        }
        if (event.code === "KeyQ") {
            camera_pos[1] += speed * delta;
        }
        if (event.code === "KeyE") {
            camera_pos[1] -= speed * delta;
        }
        if (event.code === "KeyW") {
            camera_pos[0] += speed * delta;
        }
        if (event.code === "KeyS") {
            camera_pos[0] -= speed * delta;
        }
        if (event.code === "KeyA") {
            camera_pos[2] += speed * delta;
        }
        if (event.code === "KeyD") {
            camera_pos[2] -= speed * delta;
        }
        if (event.code === "ArrowRight") {
            camera_rot[0] -= 0.05 * delta;
        }
        if (event.code === "ArrowLeft") {
            camera_rot[0] += 0.05 * delta;
        }
        if (event.code === "ArrowUp") {
            camera_rot[1] += 0.05 * delta;
        }
        if (event.code === "ArrowDown") {
            camera_rot[1] -= 0.05 * delta;
        }
        if (event.code === "F2" && !event.repeat) {
            useNormalsMode = !useNormalsMode;
        }
        if (event.code === "F4" && !event.repeat) {
            if (hideUI) {
                container.style.visibility = "hidden";
            } else {
                container.style.visibility = "visible";
            }
            hideUI = !hideUI;
        }
    });

    //document.addEventListener("blur", blurFunc);
    // onVisibilityChange(function(visible) {
    //     console.log('the page is now', visible ? 'focused' : 'unfocused');
    // });
    //canvas.style.filter = 'blur(6px)';

    gl = canvas.getContext('webgl2'); // WebGL 2

    const sb = document.querySelector('#resSelect');

    sb.onchange = (e) => {
        e.preventDefault();
        if (sb.value == "0") {
            gl.canvas.width = 220;
            gl.canvas.height = 160;
        } else if (sb.value == "1") {
            gl.canvas.width = 256;
            gl.canvas.height = 144;
        } else if (sb.value == "2") {
            gl.canvas.width = 320;
            gl.canvas.height = 200;
        } else if (sb.value == "3") {
            gl.canvas.width = 320;
            gl.canvas.height = 240;
        } else if (sb.value == "4") {
            gl.canvas.width = 640;
            gl.canvas.height = 480;
        }
    };
    // pointer lock object forking for cross browser

    // canvas.onclick = function() {
    //     canvas.requestPointerLock();
    // };

    gl.enable(gl.DEPTH_TEST);
    gl.enable(gl.BLEND);
    gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);
}

var drawScene = function() {
    // console.log(mouse);
    waterLevel = waterLevelSlider.value;
    waterLevel_text.innerHTML = "Water Level: " + waterLevel;

    cloudDensity1 = cloudSlider1.value;
    cloudDensity2 = cloudSlider2.value;
    cloud_text.innerHTML = "Clouds: " + cloudDensity1 + "/" + cloudDensity2;

    sunHeight = sunSlider.value;
    sun_text.innerHTML = "Sun: " + sunHeight;

    delta = timer.GetDelta();
    camera_rot = [mouse[0], mouse[1], 0.];
    tick_text.innerHTML = "Ticks: " + timer.GetTicks();
    delta_text.innerHTML = "Delta: " + delta;
    cam_pos_text.innerHTML = "Camera Pos: [" + camera_pos[0].toFixed(2) + "," + camera_pos[1].toFixed(2) + "," + camera_pos[2].toFixed(2) + "]";
    cam_rot_text.innerHTML = "Camera Rot: [" + camera_rot[0].toFixed(2) + "," + camera_rot[1].toFixed(2) + "," + camera_rot[2].toFixed(2) + "]";
    // var fps = 120;
    if (!paused && !document.hasFocus()) {
        //canvas.style.filter = 'blur(6px)';
        focus_text.style.visibility = "visible";
        // fps = 45;
    } else if (paused) {
        canvas.style.filter = 'blur(6px)';
        pause_text.style.visibility = "visible";
        // fps = 45;
    } else {
        canvas.style.filter = 'blur(0px)';
        pause_text.style.visibility = "hidden";
        focus_text.style.visibility = "hidden";
    }
    gStats.update();
    // console.log(timer.GetTimeInMillis());
    // setTimeout(() => {
    //     window.requestAnimationFrame(drawScene);
    // }, 1000 / fps);
    normalSceneFrame = window.requestAnimationFrame(drawScene);

    // Adjust scene for any canvas resizing
    //resize(gl.canvas);
    // Update the viewport to the current canvas size
    gl.viewport(0, 0, gl.canvas.width, gl.canvas.height);

    // Set background color to sky blue, used for debug purposes
    gl.clearColor(0.53, 0.81, 0.92, 1.0);
    gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);

    if (!paused) {
        // Update the timer
        timer.Update();
    }

    // Set uniform values of the fragment shader
    shaderProgram.SetUniformVec3("camera_position", camera_pos);
    shaderProgram.SetUniformVec3("camera_rotation", camera_rot);
    shaderProgram.SetUniformVec2("resolution", [gl.canvas.width, gl.canvas.height]);
    shaderProgram.SetUniform1f("time", timer.GetTicksInRadians());
    shaderProgram.SetUniform1f("camera_fov", camera_fov);
    shaderProgram.SetUniform1f("waterLevel", waterLevel);
    shaderProgram.SetUniform1f("cloudDensity1", cloudDensity1);
    shaderProgram.SetUniform1f("cloudDensity2", cloudDensity2);
    shaderProgram.SetUniform1f("sunHeight", sunHeight);
    shaderProgram.SetUniform1f("normalsMode", useNormalsMode);
    shaderProgram.SetUniform1f("terrainSeed", terrainSeed);
    //SetUniform1f(shaderProgram, "fractalIncrementer", timer.GetFractalIncrement());

    // Tell WebGL to draw the scene
    mesh.Draw();
}

// resizes canvas to fit browser window
var resize = function(canvas) {
    // // // Lookup the size the browser is displaying the canvas.
    // var displayWidth = canvas.clientWidth;
    // var displayHeight = canvas.clientHeight;

    // // Check if the canvas is not the same size.
    // if (canvas.width !== displayWidth || canvas.height !== displayHeight) {
    //     var devicePixelRatio = window.devicePixelRatio || 1;
    //     // Make the canvas the same size
    //     //canvas.width = displayWidth;
    //     //canvas.height = displayHeight;
    //     //const bounds = canvas.getBoundingClientRect();
    //     canvas.width = Math.round(canvas.width * window.devicePixelRatio);
    //     canvas.height = Math.round(canvas.height * window.devicePixelRatio);
    //     aspectRatio = displayWidth / displayHeight;
    // }
}

function changeCallback(event) {
    canvas = document.getElementById('game-surface');
    if (document.pointerLockElement === canvas ||
        document.mozPointerLockElement === canvas ||
        document.webkitPointerLockElement === canvas) {
        // Pointer was just locked
        // Enable the mousemove listener
        document.addEventListener("mousemove", onDocumentMouseMove, false);
    } else {
        // Pointer was just unlocked
        // Disable the mousemove listener
        document.removeEventListener("mousemove", onDocumentMouseMove, false);
        // this.unlockHook(this.element);
    }

}

function onDocumentMouseMove(event) {

    event.preventDefault();

    mouse[0] -= event.movementX / (500. - (mouseSensitivity * 10));
    mouse[1] -= event.movementY / (500. - (mouseSensitivity * 10));

}

function onVisibilityChange(callback) {
    var visible = true;

    if (!callback) {
        throw new Error('no callback given');
    }

    function focused() {
        if (!visible) {
            callback(visible = true);
        }
    }

    function unfocused() {
        if (visible) {
            callback(visible = false);
        }
    }

    // Standards:
    if ('hidden' in document) {
        visible = !document.hidden;
        document.addEventListener('visibilitychange',
            function() {
                (document.hidden ? unfocused : focused)()
            });
    }
    if ('mozHidden' in document) {
        visible = !document.mozHidden;
        document.addEventListener('mozvisibilitychange',
            function() {
                (document.mozHidden ? unfocused : focused)()
            });
    }
    if ('webkitHidden' in document) {
        visible = !document.webkitHidden;
        document.addEventListener('webkitvisibilitychange',
            function() {
                (document.webkitHidden ? unfocused : focused)()
            });
    }
    if ('msHidden' in document) {
        visible = !document.msHidden;
        document.addEventListener('msvisibilitychange',
            function() {
                (document.msHidden ? unfocused : focused)()
            });
    }
    // IE 9 and lower:
    if ('onfocusin' in document) {
        document.onfocusin = focused;
        document.onfocusout = unfocused;
    }
    // All others:
    window.onpageshow = window.onfocus = focused;
    window.onpagehide = window.onblur = unfocused;
};