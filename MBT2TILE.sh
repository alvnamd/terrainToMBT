#!/bin/bash
#source /c/Users/alvin/anaconda3/Scripts/activate maptools_env
OUTPUT_DIR=./output_tiles

# Define the low res output directory
mbtiles_lr=${OUTPUT_DIR}/low_res_rgb.mbtiles

# Define the hi res output directory
mbtiles_hr=${OUTPUT_DIR}/high_res_rgb.mbtiles

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
import sys

def extract_mbtiles(mbtiles_file, output_dir):
    print(f"Attempting to extract tiles from {mbtiles_file} to {output_dir}")
    
    if not os.path.exists(mbtiles_file):
        print(f"Error: MBTiles file {mbtiles_file} does not exist", file=sys.stderr)
        return False

    try:
        conn = sqlite3.connect(mbtiles_file)
        cursor = conn.cursor()
        
        # Check if 'tiles' table exists
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='tiles'")
        if cursor.fetchone() is None:
            print(f"Error: 'tiles' table not found in {mbtiles_file}", file=sys.stderr)
            return False

        cursor.execute("SELECT COUNT(*) FROM tiles")
        tile_count = cursor.fetchone()[0]
        print(f"Found {tile_count} tiles in the database")

        if tile_count == 0:
            print(f"No tiles found in {mbtiles_file}", file=sys.stderr)
            return False

        cursor.execute("SELECT zoom_level, tile_column, tile_row, tile_data FROM tiles")
        rows = cursor.fetchall()

        for row in rows:
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
        
        print(f"Successfully extracted {tile_count} tiles from {mbtiles_file} to {output_dir}")
        return True
    except sqlite3.Error as e:
        print(f"SQLite error occurred: {e}", file=sys.stderr)
        return False
    except Exception as e:
        print(f"An error occurred: {e}", file=sys.stderr)
        return False
    finally:
        if conn:
            conn.close()

# Extract low-res tiles
low_res_success = extract_mbtiles("${mbtiles_lr}", "${LOW_RES_DIR}")
if not low_res_success:
    print("Failed to extract low-res tiles", file=sys.stderr)

# Extract high-res tiles
high_res_success = extract_mbtiles("${mbtiles_hr}", "${HIGH_RES_DIR}")
if not high_res_success:
    print("Failed to extract high-res tiles", file=sys.stderr)

if not (low_res_success or high_res_success):
    sys.exit(1)
END

# Function to copy tiles maintaining directory structure
copy_tiles() {
    local src_dir=$1
    local dest_dir=$2
    local is_high_res=$3

    if [ -d "$src_dir" ] && [ "$(ls -A $src_dir)" ]; then
        echo "Processing tiles from $src_dir..."
        find "$src_dir" -type f -name "*.png" | while read tile; do
            rel_path=${tile#$src_dir/}
            zoom=$(echo $rel_path | cut -d'/' -f1)
            column=$(echo $rel_path | cut -d'/' -f2)
            row=$(basename $tile .png)
            
            dest_path="$dest_dir/$zoom/$column"
            mkdir -p "$dest_path"
            
            if [ "$is_high_res" = true ]; then
                # For high-res tiles, always copy (overwriting if necessary)
                cp "$tile" "$dest_path/$row.png"
            else
                # For low-res tiles, only copy if high-res version doesn't exist
                if [ ! -f "$dest_path/$row.png" ]; then
                    cp "$tile" "$dest_path/$row.png"
                fi
            fi
        done
        echo "Finished processing tiles from $src_dir"
    else
        echo "No tiles found in $src_dir"
    fi
}

# Check if at least one extraction was successful
if [ ! -d "${LOW_RES_DIR}" ] && [ ! -d "${HIGH_RES_DIR}" ]; then
    echo "Error: Both low-res and high-res tiles extraction failed or no tiles were extracted."
    exit 1
fi

echo "Tile extraction completed."

# Ensure DEST_DIR exists
mkdir -p "$DEST_DIR"

# Copy low-res tiles first, if available
if [ -d "${LOW_RES_DIR}" ] && [ "$(ls -A ${LOW_RES_DIR})" ]; then
    copy_tiles "$LOW_RES_DIR" "$DEST_DIR" false
fi

# Copy high-res tiles, if available, overwriting low-res tiles where applicable
if [ -d "${HIGH_RES_DIR}" ] && [ "$(ls -A ${HIGH_RES_DIR})" ]; then
    copy_tiles "$HIGH_RES_DIR" "$DEST_DIR" true
fi

echo "Tile moving complete. All tiles are now in $DEST_DIR"

# Count the number of tiles in the combined directory
tile_count=$(find "$DEST_DIR" -type f -name "*.png" | wc -l)
echo "Total number of tiles in combined directory: $tile_count"

# Remove the now-empty source directories
rm -rf "$LOW_RES_DIR"
rm -rf "$HIGH_RES_DIR"
