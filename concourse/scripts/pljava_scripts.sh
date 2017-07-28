pljava_build() {
  GREEN='\033[0;32m'
  RED='\033[0;31m'
  NC='\033[0m' # No Color

  build_attempt=1
  max_attempts=3
  while [ "$build_attempt" -le "$max_attempts" ]; do
    printf "${GREEN}Building PL/Java - Attempt $build_attempt${NC}...\n\n"

    if make; then
      printf "\n${GREEN}Successfully built${NC}.\n\n"
      return
    fi

    build_attempt=$(expr "$build_attempt" + 1)
  done

  printf "\n${RED}Failed to build PL/Java.${NC}\n"
  exit 1
}