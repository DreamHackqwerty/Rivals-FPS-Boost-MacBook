#!/bin/bash

# Prompt the user for confirmation
echo "Do you want to implement these performance boosts? It will unlock FPS and boost FPS but might crash Roblox and make the graphics blurry."
read -p "Type 'yes' to continue or anything else to cancel: " CONFIRM

# Check if the user confirmed
if [ "$CONFIRM" != "yes" ]; then
    echo "Operation canceled. No changes were made."
    exit 1
fi

# Define the directory and file path
DIR="/Applications/Roblox/Contents/MacOS/ClientSettings"
FILE="$DIR/ClientAppSettings.json"

# Create the directory if it doesn't exist
mkdir -p "$DIR"

# Write the JSON content to the file
cat <<EOF > "$FILE"
{
 "DFFlagDebugPauseVoxelizer": "True",
 "DFFlagDebugPerfMode": "True",
 "DFFlagDebugRenderForceTechnologyVoxel": "True",
 "DFIntCullFactorPixelThresholdShadowMapHighQuality": "2147483647",
 "DFIntCullFactorPixelThresholdShadowMapLowQuality": "2147483647",
 "DFIntMaxFrameBufferSize": "3",
 "DFIntPerformanceControlTextureQualityBestUtility": "-1",
 "DFIntTaskSchedulerTargetFps": "666",
 "FFlagDebugDisplayFPS": "True",
 "FFlagDebugGraphicsDisableMetal": "True",
 "FFlagDebugGraphicsPreferVulkan": "True",
 "FFlagDebugSkyGray": "True",
 "FIntDebugTextureManagerSkipMips": "3",
 "FIntRenderShadowIntensity": "0",
 "FIntTerrainArraySliceSize": "0",
 "FLogNetwork": "7"
}
EOF

# Check if the file was created successfully
if [ -f "$FILE" ]; then
    echo "ClientAppSettings.json has been successfully created at $FILE"
else
    echo "Failed to create ClientAppSettings.json"
fi