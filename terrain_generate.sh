#!/bin/bash
#source /c/Users/alvin/anaconda3/Scripts/activate maptools_env

INPUT_LOW_RES=./input/low_res
INPUT_HIGH_RES=./input/high_res
OUTPUT_DIR=./output_tiles

# Define the low res output directory
vrtfile_lr=${OUTPUT_DIR}/jaxa_terrainrgb.vrt
vrtfile2_lr=${OUTPUT_DIR}/jaxa_terrainrgb_warp.vrt
mbtiles_lr=${OUTPUT_DIR}/jaxa_terrainrgb.mbtiles

# Define the hi res output directory
vrtfile_hr=${OUTPUT_DIR}/DEMNAS.vrt
vrtfile2_hr=${OUTPUT_DIR}/DEMNAS_warp.vrt
mbtiles_hr=${OUTPUT_DIR}/DEMNAS.mbtiles

[ -d "$OUTPUT_DIR" ] || mkdir -p $OUTPUT_DIR || { echo "error: $OUTPUT_DIR " 1>&2; exit 1; }

# Rgbify low & hi res data
gdalbuildvrt -overwrite -srcnodata -9999 -vrtnodata -9999 ${vrtfile_lr} ${INPUT_LOW_RES}/*.tif
gdalwarp -r cubicspline -t_srs EPSG:4326 -dstnodata 0 -co COMPRESS=DEFLATE ${vrtfile_lr} ${vrtfile2_lr}
rio rgbify -b -10000 -i 0.1 --min-z 0 --max-z 7 -j 24 --format png ${vrtfile2_lr} ${mbtiles_lr}

gdalbuildvrt -overwrite -srcnodata -9999 -vrtnodata -9999 ${vrtfile_hr} ${INPUT_HIGH_RES}/*.tif
gdalwarp -r cubicspline -t_srs EPSG:4326 -dstnodata 0 -co COMPRESS=DEFLATE ${vrtfile_hr} ${vrtfile2_hr}
rio rgbify -b -10000 -i 0.1 --min-z 8 --max-z 14 -j 24 --format png ${vrtfile2_hr} ${mbtiles_hr}

# Define the source directories
HIGH_RES_DIR="./high_res_tiles"
LOW_RES_DIR="./low_res_tiles"

# Define the destination directory
DEST_DIR="./combined_tiles"
# Create directories if they don't exist
mkdir -p ${HIGH_RES_DIR}
mkdir -p ${LOW_RES_DIR}

# Python script to extract MBTiles
python - << END
import sqlite3
import os
import zlib

def extract_mbtiles(mbtiles_file, output_dir):
    conn = sqlite3.connect(mbtiles_file)
    cursor = conn.cursor()
    cursor.execute("SELECT zoom_level, tile_column, tile_row, tile_data FROM tiles")
    for row in cursor:
        zoom, column, row, data = row
        tile_dir = os.path.join(output_dir, str(zoom), str(column))
        os.makedirs(tile_dir, exist_ok=True)
        tile_path = os.path.join(tile_dir, f"{row}.png")
        try:
            tile_data = zlib.decompress(data)
        except zlib.error:
            tile_data = data  # If decompression fails, assume it's already uncompressed
        with open(tile_path, 'wb') as f:
            f.write(tile_data)
    conn.close()

extract_mbtiles("${mbtiles_hr}", "${HIGH_RES_DIR}")
extract_mbtiles("${mbtiles_lr}", "${LOW_RES_DIR}")
END

# Create the destination directory if it doesn't exist
mkdir -p "$DEST_DIR"

# Move contents of high_res_tiles to the destination directory
echo "Moving high resolution tiles..."
mv "$HIGH_RES_DIR"/* "$DEST_DIR" 2>/dev/null || true

# Move contents of low_res_tiles to the destination directory
echo "Moving low resolution tiles..."
mv "$LOW_RES_DIR"/* "$DEST_DIR" 2>/dev/null || true

echo "Tile moving complete. All tiles are now in $DEST_DIR"

# Remove the now-empty source directories
rm -rf "$HIGH_RES_DIR"
rm -rf "$LOW_RES_DIR"
rm -rf "$OUTPUT_DIR"