#!/bin/bash

# Arguments
#  $1: foreground dir
#  $2: background dir
#  $3: output base name
#  $4: process background? (True/False)
#  $5: process foreground? (True/False)
#  $6: run web filter? (True/False)
#  $7: max number of terms
#  $8: top N terms to keep
#  $9: termolator dir
# $10: treetagger dir
# $11: lang model cutoff (-1, -.2, False)

set -e

foreground_dir="${1%/}"
background_dir="${2%/}"
outname="$3"
termolator_dir="${9%/}"
treetagger_dir="${10%/}"
lang_model_cutoff="$11"

# Function to preprocess directory
preprocess_dir() {
  local dir=$1
  local label=$2

  echo "--- Language modeling: $label ---"
  bash "$termolator_dir/run_lang_model_${label}_fr.sh" "$dir" "$lang_model_cutoff" "$termolator_dir"

  echo "--- Tagging documents: $label ---"
  bash "$termolator_dir/tag_back_and_foreground.sh" "$dir" "$treetagger_dir"

  echo "--- Creating file list: $label ---"
  bash "$termolator_dir/make_file_list.sh" "${dir}_tagged/"
  python3 "$termolator_dir/file_list_error_fudge.py" "${dir}_tagged_list.txt"

  echo "--- Extracting noun chunks: $label ---"
  java -cp "$termolator_dir" getNounChunks "${dir}_tagged_list.txt"

  echo "--- Running stage 1 filter: $label ---"
  python3 "$termolator_dir/stage1_driver.py" "${dir}_tagged_list.chunklist"
}

if [ "${4,,}" = "true" ]; then
  preprocess_dir "$background_dir" "background"
fi

if [ "${5,,}" = "true" ]; then
  preprocess_dir "$foreground_dir" "foreground"
fi

echo "--- Creating .terms files from .chunks ---"
while read filepath; do
  basefile=$(basename "$filepath" .txt_tagged)
  chunkfile="${foreground_dir}_tagged/${basefile}.chunks"
  termsfile="${foreground_dir}_tagged/${basefile}.terms"
  if [ -f "$chunkfile" ]; then
    cp "$chunkfile" "$termsfile"
  fi
done < "${foreground_dir}_tagged_list.txt"

python3 "$termolator_dir/make_io_file.py" \
  "${foreground_dir}_tagged_list.txt" \
  "${outname}.internal_terms_abbr_list" \
  .terms

echo "--- Extracting inline abbreviations ---"
python3 "$termolator_dir/run_find_inline_terms.py" \
  "${outname}.internal_terms_abbr_list" \
  false \
  "${outname}" \
  "${outname}.dict_abbr_to_full"




echo "--- Creating IO mapping files ---"
python3 "$termolator_dir/make_io_file.py" "${foreground_dir}_tagged_list.txt" "${outname}.internal_foreground_abbr_list" .abbr
python3 "$termolator_dir/make_io_file.py" "${foreground_dir}_tagged_list.txt" "${outname}.internal_foreground_substring_list" .substring
python3 "$termolator_dir/make_io_file.py" "${background_dir}_tagged_list.txt" "${outname}.internal_background_abbr_list" .abbr
python3 "$termolator_dir/make_io_file.py" "${background_dir}_tagged_list.txt" "${outname}.internal_background_substring_list" .substring


echo "--- Running distributional component ---"
python3 "$termolator_dir/distributional_component.py" NormalRank \
  "${foreground_dir}_tagged_list.chunklist.substring_list" \
  "${outname}.all_terms" \
  False \
  "${background_dir}_tagged_list.chunklist.substring_list"




echo "--- Creating abbreviation dictionaries ---"
python3 "$termolator_dir/possibly_create_abbreviate_dicts.py" \
  "${outname}.internal_foreground_abbr_list" \
  "${outname}.dict_full_to_abbr" \
  "${outname}.dict_abbr_to_full"

echo "--- Generating term and substring lists ---"
python3 "$termolator_dir/run_make_term_and_substring_list.py" \
  "${outname}.internal_terms_abbr_list" \
  "${outname}.dict_abbr_to_full" \
  False \
  "${outname}_lemma.dict"


echo "--- Filtering and scoring terms ---"
python3 "$termolator_dir/filter_term_output_fr.py" \
  "$outname" \
  "${outname}.webscore" \
  "$6" \
  "$7" \
  "${outname}.internal_foreground_abbr_list" \
  False

head -n "$8" "${outname}.scored_output" | cut -f 1 > "${outname}.out_term_list"
echo "✅ Done. Output written to ${outname}.scored_output and ${outname}.out_term_list"
