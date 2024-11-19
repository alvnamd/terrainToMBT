#!/bin/bash
#source /c/Users/alvin/anaconda3/Scripts/activate maptools_env

INPUT_LOW_RES=./input/low_res
INPUT_HIGH_RES=./input/high_res
OUTPUT_DIR=./output_tiles

# Define the low res output directory
vrtfile_lr=${OUTPUT_DIR}/low_res_rgb.vrt
vrtfile2_lr=${OUTPUT_DIR}/low_res_rgb_warp.vrt
mbtiles_lr=${OUTPUT_DIR}/low_res_rgb.mbtiles

# Define the hi res output directory
vrtfile_hr=${OUTPUT_DIR}/high_res_rgb.vrt
vrtfile2_hr=${OUTPUT_DIR}/high_res_rgb_warp.vrt
mbtiles_hr=${OUTPUT_DIR}/high_res_rgb.mbtiles

[ -d "$OUTPUT_DIR" ] || mkdir -p $OUTPUT_DIR || { echo "error: $OUTPUT_DIR " 1>&2; exit 1; }

# Rgbify low res data
gdalbuildvrt -overwrite -srcnodata -9999 -vrtnodata -9999 ${vrtfile_lr} ${INPUT_LOW_RES}/*.tif
gdalwarp -r cubicspline -t_srs EPSG:4326 -dstnodata 0 -co COMPRESS=DEFLATE ${vrtfile_lr} ${vrtfile2_lr}
rio rgbify -b -10000 -i 0.1 --min-z 0 --max-z 13 -j 24 --format webp ${vrtfile2_lr} ${mbtiles_lr}

# Rgbify high res data
gdalbuildvrt -overwrite -srcnodata -9999 -vrtnodata -9999 ${vrtfile_hr} ${INPUT_HIGH_RES}/*.tif
gdalwarp -multi -r cubicspline -t_srs EPSG:4326 -dstnodata 0 -co COMPRESS=DEFLATE -co BIGTIFF=YES ${vrtfile_hr} ${vrtfile2_hr}
rio rgbify -b -10000 -i 0.1 --min-z 8 --max-z 14 -j 24 --format webp ${vrtfile2_hr} ${mbtiles_hr}

# Check if MBTiles files were created
if [ ! -f "${mbtiles_lr}" ]; then
    echo "Error: Low-res MBTiles file was not created."
    exit 1
fi

if [ ! -f "${mbtiles_hr}" ]; then
    echo "Error: High-res MBTiles file was not created."
    exit 1
fi

echo "MBTiles files created successfully."