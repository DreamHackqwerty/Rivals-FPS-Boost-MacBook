import time, os, math, sys, json
from java.lang import System
from java.lang import Math
from nu.pattern import OpenCV
OpenCV.loadShared()
#from sikuli import *
from org.opencv.core import Mat, Scalar, Core, CvType, Size, MatOfPoint, MatOfByte
from org.opencv.imgcodecs import Imgcodecs
from org.opencv.imgproc import Imgproc
from java.awt.image import BufferedImage
from javax.swing import JFrame
from java.awt import Color, Robot, Rectangle, Toolkit
from java.util import ArrayList
from java.io import ByteArrayOutputStream
from javax.imageio import ImageIO
import time, os, math, sys, json
from java.lang import System 
Settings.MoveMouseDelay = 0.01
Settings.ActionLogs=0
#Debug.on(3)
SCRIPT_DIR = os.path.join(os.path.dirname(getBundlePath()), "macro.sikuli")
DATA_FILE = os.path.join(SCRIPT_DIR, "data.json")

# Load data from JSON file
data = None
if os.path.exists(DATA_FILE):
    try:
        with open(DATA_FILE, 'r') as file:
            data = json.load(file)
    except Exception as e:
        print("Error loading data.json: ".format(e))
else:
    print("File not found: data.json")

# Configuration from JSON
ROBLOX = "Roblox" if not data.get("IsLinux", False) else "Sober"
TIME_EACH_LOOP = 5
LATENCY = data.get("ShakeSpeed", 0.5)
SHAKE_ENABLED = data.get("ShakeEnabled", True)
IS_CLICK_SHAKE = data.get("ClickShake", True)

# Color sets for detection
COLOR_SETS = {
    "Color_Fish": {"0x434b5b": 3, "0x4a4a5c": 4, "0x47515d": 4},
    "Color_White": {"0xFFFFFF": 15},
    "Color_Bar": {"0x848587": 4, "0x787773": 4, "0x7a7873": 4}
}

# Global flags
running = True
is_shaking = False
is_catching = False

# Hotkey to stop the script
def run_hotkey(event):
    global running
    print("Hotkey pressed: Stopping script.")
    running = False

Env.addHotkey("x", KeyModifier.CTRL, run_hotkey)

# Initialize Roblox window
roblox_app = App(ROBLOX)

# Check if Roblox is running
if not roblox_app.isRunning():
    print("Roblox is not running. Please start Roblox first.")
    exit(1)

# Focus the Roblox window
switchApp(ROBLOX)

# Get the focused window
roblox_window = roblox_app.focusedWindow()
if roblox_window is None:
    print("Failed to focus Roblox window. Please ensure it is open and visible.")
    exit(1)

# Create the region
roblox_window_region = Region(roblox_window)
# Scaling factors for compatibility
REFERENCE_RESOLUTION = [1440, 875]
CURRENT_RESOLUTION = [roblox_window_region.w, roblox_window_region.h]
SCALE_FACTOR = [float(CURRENT_RESOLUTION[0]) / 1920.0, float(CURRENT_RESOLUTION[1]) / 1200.0]

# Reeling region
REELING_REGION = Region(
    int(561.0 * SCALE_FACTOR[0]),
    int(1027.0 * SCALE_FACTOR[1]),
    int(807.0 * SCALE_FACTOR[0]),
    int(3.0 * SCALE_FACTOR[1])
)

# Overlay for debugging
def create_overlay(color, width=20, height=35):
    frame = JFrame()
    frame.setSize(width, height)
    frame.setUndecorated(True)
    frame.setAlwaysOnTop(True)
    frame.getContentPane().setBackground(color)
    frame.setVisible(True)
    return frame

# Fish bar detector class
class FishBarDetector:
    def __init__(self):
        self.window_width = CURRENT_RESOLUTION[0]
        self.window_height = CURRENT_RESOLUTION[1]
        x1, x2 = int(self.window_width / 3.3), int(self.window_width / 1.43)
        y1, y2 = int(self.window_height / 1.20), int(self.window_height / 1.15)
        print()
        print(x1,x2,y1,y2)
        #self.region = Region(min(x1, x2), min(y1, y2), abs(x2 - x1), abs(y2 - y1))
        self.region = Region(421,698,593,58)
        # Color detection setup
        hex_color = "#414c5b"
        bgr_color = tuple(int(hex_color[i:i+2], 16) for i in (1, 3, 5))
        bgr_color = (bgr_color[2], bgr_color[1], bgr_color[0])
        bgr_mat = Mat(1, 1, CvType.CV_8UC3, Scalar(*bgr_color))
        hsv_mat = Mat()
        Imgproc.cvtColor(bgr_mat, hsv_mat, Imgproc.COLOR_BGR2HSV)
        hsv_color = list(hsv_mat.get(0, 0))

        hex_tolerance, white_tolerance = 12, 4
        self.lower_bound = Scalar(max(0, hsv_color[0] - hex_tolerance),
                                 max(0, hsv_color[1] - hex_tolerance),
                                 max(0, hsv_color[2] - hex_tolerance))
        self.upper_bound = Scalar(min(179, hsv_color[0] + hex_tolerance),
                                 min(255, hsv_color[1] + hex_tolerance),
                                 min(255, hsv_color[2] + hex_tolerance))
        self.lower_white = Scalar(0, 0, 255 - white_tolerance)
        self.upper_white = Scalar(255, white_tolerance, 255)
        self.min_fish_height = 20
        self.last_known_bar = None
        self.last_bar_detection_time = None
    def _capture_screen(self, region=None):
        robot = Robot()
        if region:
            return robot.createScreenCapture(Rectangle(region.x, region.y, region.w, region.h))
        else:
            screen_size = Toolkit.getDefaultToolkit().getScreenSize()
            return robot.createScreenCapture(Rectangle(screen_size))

    def _convert_to_mat(self, buffered_image):
        baos = ByteArrayOutputStream()
        ImageIO.write(buffered_image, "png", baos)
        byte_array = baos.toByteArray()
        mat_of_byte = MatOfByte(byte_array)
        return Imgcodecs.imdecode(mat_of_byte, Imgcodecs.IMREAD_COLOR)

    def _merge_boxes(self, boxes, min_distance=20):
        if not boxes:
            return []
        boxes = sorted(boxes, key=lambda b: b[0])
        merged_boxes = [boxes[0]]
        for box in boxes[1:]:
            last_box = merged_boxes[-1]
            if box[0] <= last_box[0] + last_box[2] + min_distance:
                merged_box = (
                    min(last_box[0], box[0]),
                    min(last_box[1], box[1]),
                    max(last_box[0] + last_box[2], box[0] + box[2]) - min(last_box[0], box[0]),
                    max(last_box[1] + last_box[3], box[1] + box[3]) - min(last_box[1], box[1]),
                )
                merged_boxes[-1] = merged_box
            else:
                merged_boxes.append(box)
        return merged_boxes

    def _get_combined_box(self, boxes):
        if not boxes:
            return None
        x_min = min(box[0] for box in boxes)
        y_min = min(box[1] for box in boxes)
        x_max = max(box[0] + box[2] for box in boxes)
        y_max = max(box[1] + box[3] for box in boxes)
        return (x_min, y_min, x_max - x_min, y_max - y_min)

    def find_objects(self):
        try:
            start = time.time()  # Initialize 'start' for timing
            screenshot = self._capture_screen(self.region)
            frame = self._convert_to_mat(screenshot)
            hsv_frame = Mat()
            Imgproc.cvtColor(frame, hsv_frame, Imgproc.COLOR_BGR2HSV)

            # Detect Fish (Red Box)
            mask_hex_color = Mat()
            Core.inRange(hsv_frame, self.lower_bound, self.upper_bound, mask_hex_color)
            contours_hex = ArrayList()
            Imgproc.findContours(mask_hex_color, contours_hex, Mat(), Imgproc.RETR_EXTERNAL, Imgproc.CHAIN_APPROX_SIMPLE)

            largest_hex = None
            max_area = 0
            for contour in contours_hex:
                rect = Imgproc.boundingRect(contour)
                if rect.height >= self.min_fish_height:
                    area = rect.width * rect.height
                    if area > max_area:
                        max_area = area
                        largest_hex = rect

            fish = None
            if largest_hex:
                x, y, w, h = largest_hex.x, largest_hex.y, largest_hex.width, largest_hex.height
                # Convert to absolute screen coordinates
                fish = (self.region.x + x + w // 2, self.region.y + y + h // 2)

            # Detect Bar (Green Box)
            mask_white = Mat()
            Core.inRange(hsv_frame, self.lower_white, self.upper_white, mask_white)
            contours_white = ArrayList()
            Imgproc.findContours(mask_white, contours_white, Mat(), Imgproc.RETR_EXTERNAL, Imgproc.CHAIN_APPROX_SIMPLE)

            white_boxes = []
            for contour in contours_white:
                rect = Imgproc.boundingRect(contour)
                if rect.width > 50:
                    white_boxes.append((rect.x, rect.y, rect.width, rect.height))

            merged_white_boxes = self._merge_boxes(white_boxes)
            combined_box = self._get_combined_box(merged_white_boxes)
            bar = None
            if combined_box:
                x, y, w, h = combined_box
                # Convert to absolute screen coordinates
                left_width = x + w // 2 - (x)  # Distance from left edge to center
                right_width = (x + w) - x + w // 2
                bar = (self.region.x + x + w // 2, self.region.y + y + h // 2,w,h)
            print("Fish:", fish, "Bar:", bar, "Time Elapsed:", time.time() - start)
            time.sleep(0.01)

            if fish is None and bar is None:
                return (0, 0), (0, 0,0,0)
            elif bar is None:
                return fish, (0, 0,0,0)
            elif fish is None:
                return (0, 0), bar
            return fish, bar

        except Exception as e:
            print("Error in find_objects: {}".format(e))
            return (0, 0), (0, 0)
count = 0
def Catch():
    global count
    start_time = time.time()
    e_time = time.time()
    prev_target_x = None
    stationary_start_time = None
    three_quarter_mark = REELING_REGION.x + (REELING_REGION.w * 0.85)
    timeout = 2
    control = data.get("Control", 1.0)  # Default to 1.0 if missing
    result = round((CURRENT_RESOLUTION[1] / 247.03) * (control * 100) + (CURRENT_RESOLUTION[1] / 8.2759), 0)
    # Create an instance of FishBarDetector
    detector = FishBarDetector()

    # Overlays for debugging
    frame_bar = create_overlay(Color.BLACK)  # Tracks bar position
    frame_target = create_overlay(Color.WHITE)  # Tracks fish/target position

    last_valid_target_x = None
    last_valid_bar_x = None
    last_valid_bar = None

    while True:
        if running == False:
            frame_bar.dispose()
            frame_target.dispose()
            return
        print("-----------------TEST-----------------")

        # Use FishBarDetector to find fish and bar positions
        fish, bar = detector.find_objects()

        # Extract x values (fallback to 0 if not detected)
        target_x = fish[0] if fish else 0
        target_y = fish[1] if fish else 0

        bar_x = bar[0] if bar else 0
        bar_y = bar[1] if bar else 0

        if target_x == 0:
            count = count + 1
            print("COUNTED POINT:",count)
            if count >= 5: 
                break
        else:
            count = 0
        # Handle missing positions (use last valid if available)
        if target_x == 0 and last_valid_target_x is not None:
            target_x = last_valid_target_x
        if bar_x == 0 and last_valid_bar is not None:
            bar_x = last_valid_bar_x
            bar_y = last_valid_bar[2] if last_valid_bar else 0
            bar = last_valid_bar
            

        # Check if target is stationary at the 3/4 mark
        if target_x > three_quarter_mark:
            if prev_target_x is not None and abs(target_x - prev_target_x) < 30:  # Small movement threshold
                if stationary_start_time is None:
                    stationary_start_time = time.time()
                # Hold the mouse if stationary for 1 second
                if time.time() - stationary_start_time >= 1:
                    print("Mouse held at 3/4 mark until target moves...")
                    mouseDown(Button.LEFT)
                    continue
            else:
                stationary_start_time = None  # Reset if target moves
            prev_target_x = target_x
        else:
            stationary_start_time = None  # Reset if target moves before 3/4 mark
            mouseUp(Button.LEFT)

        # Timeout check
        if time.time() - start_time > timeout:
            print("Loop timed out. Exiting...")
            break

        # Update overlays and handle mouse actions
        if target_x != 0:
            frame_target.setLocation(int(target_x), int(target_y))
            start_time = time.time()
            last_valid_target_x = target_x

            
            if bar_x != 0:
                frame_bar.setLocation(int(bar_x), int(bar_y))
                last_valid_bar_x = bar_x

            # Calculate distance between target and bar
            distance = target_x - bar_x
            close_threshold = 15 * (bar[2]/60)
            left_threshold = -50 * (bar[2]/60)
            right_threshold = 50 * (bar[2]/60)
            print(close_threshold,left_threshold,right_threshold)

            # Adjust mouse based on distance
            if distance <= right_threshold:
                mouseDown(Button.LEFT)
            elif distance >= left_threshold:
                mouseDown(Button.LEFT)
                time.sleep(1* distance/10000)
                mouseUp(Button.LEFT)
                time.sleep(1 * distance/1000)
            elif abs(distance) < close_threshold:
                mouseDown(Button.LEFT)
                time.sleep(0.01)
                mouseUp(Button.LEFT)
            elif distance > close_threshold:
                mouseDown(Button.LEFT)
                time.sleep(0.003)
                mouseUp(Button.LEFT)
        else:
            print("Target value not found: Count = {}".format(count))
            if count >= 5: 
                break
    
    # Clean up overlays
    frame_bar.dispose()
    frame_target.dispose()
    return
# Shake Functions
def ClickShake():
    global LATENCY
    userbarColor = COLOR_SETS["Color_White"]
    screen = Screen()
    detection = FishBarDetector()
    while True:
        shake = Pattern("shake.png").similar(0.50)
        if exists(shake, 0.1):
            try:
                click(shake)
            except:
                time.sleep(LATENCY)
        else:
            print("CATCHING")
            global is_shaking
            is_shaking = False
            break
    return True

def NavigationShake():
    global LATENCY
    userbarColor = COLOR_SETS["Color_White"]
    screen = Screen()
    detection = FishBarDetector()
    type("\\")
    while True:
        fish, bar = detection.find_objects()
        keyDown(Key.PAGE_DOWN)
        wait(0.5)
        keyUp(Key.PAGE_DOWN)
        shake = Pattern("better_shake.png").similar(0.50)
        if exists(shake):
            keyDown(Key.ENTER)
            wait(0.4)
            keyUp(Key.ENTER)
            wait(LATENCY)
        elif not exists(shake):
            type("\\")
            return True
        elif fish[1] != 0:
            print("CATCHING")
            type("\\")
            return True
        else:
            print("FAILED")
            global is_shaking
            is_shaking = False
            return True

# Main loop

while running:
    
    App.focus(ROBLOX)
    mouseDown(Button.LEFT)
    time.sleep(data.get("CastDuration", 1.0))
    mouseUp(Button.LEFT)
    time.sleep(0.5)
    e = True
    if SHAKE_ENABLED:
        if IS_CLICK_SHAKE:
            e = ClickShake()
        else:
            e = NavigationShake()
    if e == True:
        time.sleep(1.5)
        print("User is catching...")
        Catch()