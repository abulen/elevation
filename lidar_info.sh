#!/bin/bash
# lidar_info
#
# Generates vector dataset of lidar file metadata
#
# author: abulen
# Requires:
# - PDAL
# - GDAL
# - (rclone: for indexing all files from url path)
src=$1
dst=$2

feature() {
  f_src=$1
  f_dst=$2
  # extract las info
  json=$(pdal info --metadata --stats --filters.stats.count="ReturnNumber,NumberOfReturns,Classification,PointSourceId,Synthetic,Withheld,Overlap" $f_src)
  # parse to csv
  csv=$(jq --raw-output '["location", "size", "major_version", "minor_version", "global_encoding",
  "compressed", "copc", "point_count",
  "srs", "srs_wkt",
  "horizontal_epsg", "vertical_epsg", "geoid",
  "horizontal_units", "vertical_units",
  "minx", "maxx", "miny", "maxy", "minz", "maxz",
  "gps_min", "gps_max",
  "return_number",
  "number_of_returns",
  "classifications",
  "point_src_ids",
  "synthetic",
  "withheld",
  "overlap",
  "stats_minx", "stats_maxx", "stats_miny", "stats_maxy", "stats_minz", "stats_maxz",
  "geometry", "info"] as $header |
  [.filename, .file_size, .metadata.major_version, .metadata.minor_version, .metadata.global_encoding,
  .metadata.compressed, .metadata.copc, .metadata.count,
  .metadata.srs.json.components[0].name, .metadata.spatialreference,
  (if .metadata.srs.json.components[0].id ? then .metadata.srs.json.components[0].id.code else "unknown" end),
  (if .metadata.srs.json.components[1].id ? then .metadata.srs.json.components[1].id.code else "unknown" end),
  (if .metadata.srs.json.components[1].geoid_model ? then .metadata.srs.json.components[1].geoid_model.name else "unknown" end),
  .metadata.srs.units.horizontal, .metadata.srs.units.vertical,
  .metadata.minx, .metadata.maxx, .metadata.miny, .metadata.maxy, .metadata.minz, .metadata.maxz,
  (.stats.statistic[] | select(.name == "GpsTime")| .minimum, .maximum),
  (.stats.statistic[] | select(.name == "ReturnNumber")| .counts | join(",")),
  (.stats.statistic[] | select(.name == "NumberOfReturns")| .counts | join(",")),
  (.stats.statistic[] | select(.name == "Classification")| .counts | join(",")),
  (.stats.statistic[] | select(.name == "PointSourceId")| .counts | join(",")),
  (.stats.statistic[] | select(.name == "Synthetic")| .counts | join(",")),
  (.stats.statistic[] | select(.name == "Withheld")| .counts | join(",")),
  (.stats.statistic[] | select(.name == "Overlap")| .counts | join(",")),
  (.stats.statistic[] | select(.name == "X")| .minimum, .maximum),
  (.stats.statistic[] | select(.name == "Y")| .minimum, .maximum),
  (.stats.statistic[] | select(.name == "Z")| .minimum, .maximum),
  (.stats.bbox.native.boundary | tostring), (. | tostring)] as $data |
  $header, $data | @csv' <<< "$json")
  # extract horizontal srs
  srs=$(jq --raw-output '.metadata.srs.horizontal' <<< "$json")
  # convert csv to feature
  if [[ -z $f_dst ]]; then
    ogr2ogr -oo GEOM_POSSIBLE_NAMES=geometry -oo KEEP_GEOM_COLUMNS=NO -a_srs "$srs" -f GeoJSON /vsistdout/ CSV:/vsistdin/ <<< "$csv"
  else
    ogr2ogr -oo GEOM_POSSIBLE_NAMES=geometry -oo KEEP_GEOM_COLUMNS=NO -a_srs "$srs" "$f_dst" CSV:/vsistdin/ <<< "$csv"
  fi
}

directory(){
  d_src=$1
  d_dst=$2
  # find lidar files
  if [[ -d $d_src ]]; then
    readarray -d '' paths < <(find "$d_src" -type f -regextype posix-egrep -regex ".*\.(las|laz)$" -print0)
  else
    url=$d_src
    if [[ "$url" == *"/" ]]; then
      jq_url="$url"
      url="${url::-1}"
    else
      jq_url="$url/"
    fi
    json=$(rclone lsjson --files-only -R --include=**.laz --http-url $url :http:)
    readarray -t paths < <(jq --raw-output --arg url $jq_url 'map($url + .Path) | .[]'  <<< "$json")
  fi
  # create features
  for path in "${paths[@]}"
  do
    name=$(basename -- "$path")
    tmp="/tmp/${name%.*}.geojson"
    feature "$path" "$tmp"
    if [[ -f $d_dst ]]; then
      ogr2ogr -append "$d_dst" "$tmp"
    else
      ogr2ogr "$d_dst" "$tmp"
    fi
    rm "$tmp"
  done
}


# Remove existing output dataset
if [[ -f $dst ]]; then
  rm "$dst"
fi

if [[ $src == *".las" || $src == *".laz" ]]; then
  feature "$src" "$dst"
else
  directory "$src" "$dst"
fi
