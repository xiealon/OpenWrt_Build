#!/usr/bin/env bash
#
# 2025 Alon <https://github.com/xiealon> apply and modify to Ing wjz304
#
# This is free software, licensed under the MIT License.
# See /LICENSE for more information.
#

if [ -z "${1}" ] || [ ! -f "${1}" ]; then
  echo "Usage: $0 <config file>"
  exit 1
fi

WORK_PATH="$(pwd)"

SCRIPT_FILE="${WORK_PATH}/diy.sh"
CONFIG_FILE=$(realpath "${1}")                        # 传入的配置文件
ALON_PATH=$(dirname "${CONFIG_FILE}")                 # 配置Alon源路径
CONFIG_PATH=$(dirname "${CONFIG_FILE}")               # 配置文件路径
CONFIG_NAME=$(basename "${CONFIG_FILE}" .config)      # 配置文件名
IFS=';' read -r -a CONFIG_ARRAY <<< "${CONFIG_NAME}"  # 分割配置文件名

GITHUB_ACTIONS="${2:-false}"

if [ ${#CONFIG_ARRAY[@]} -ne 3 ]; then
  echo "${CONFIG_FILE} name error!" # config 命名规则: <repo>;<owner>;<name>.config
  exit 1
fi

CONFIG_REPO="${CONFIG_ARRAY[0]}"
CONFIG_OWNER="${CONFIG_ARRAY[1]}"
CONFIG_ARCH="${CONFIG_ARRAY[2]}"

if [ "${CONFIG_REPO}" = "lede" ]; then
  REPO_URL="https://github.com/xiealon/lede"
  REPO_BRANCH="master"
else
  echo "${CONFIG_FILE} name error!"
  exit 1
fi

if [ ! -d "${WORK_PATH}/${CONFIG_REPO}" ]; then
  git clone --depth=1 -b "${REPO_BRANCH}" "${REPO_URL}" "${WORK_PATH}/${CONFIG_REPO}"
  if [ -d "${CONFIG_REPO}/package/kernel/r8125" ]; then
    rm -rf "${CONFIG_REPO}/package/kernel/r8125"
  fi
  if [ -d "${CONFIG_REPO}/package/lean/r8152" ]; then
     rm -rf "${CONFIG_REPO}/package/lean/r8152"
  fi
fi

# root.
export FORCE_UNSAFE_CONFIGURE=1

pushd "${WORK_PATH}/${CONFIG_REPO}" || exit

git pull

cp -f "${ALON_PATH}/alon.sh" "./alon.sh"
 if [ $? -ne 0 ]; then
   echo "Failed to copy the alon.sh."
   exit 1
 else
   echo "Successfully updated copy the alon.sh"
 fi

chmod +x "./alon.sh"
 if [ $? -ne 0 ]; then
   echo "Failed to chmod x to alon.sh."
   exit 1
 else
   echo "Successfully updated alon.sh chmod"
 fi

"./alon.sh" "${CONFIG_REPO}" # "${CONFIG_OWNER}" # "${CONFIG_ARCH}"
 if [ $? -ne 0 ]; then
   echo "Failed to run alon.sh."
   exit 1
 else
   echo "Successfully updated alon.sh to run"
 fi

cp -f "${CONFIG_FILE}" "./.config"
 if [ $? -ne 0 ]; then
   echo "Failed to copy config."
   exit 1
 else
   echo "Successfully updated config to copy"
 fi
 
cp -f "${ALON_PATH}/diy.sh" "./diy.sh"
 if [ $? -ne 0 ]; then
   echo "Failed to copy diy.sh."
   exit 1
 else
   echo "Successfully updated diy.sh to copy"
 fi

chmod +x "./diy.sh"
 if [ $? -ne 0 ]; then
   echo "Failed to chmod x to diy.sh."
   exit 1
 else
   echo "Successfully updated diy.sh chmod"
 fi
 
"./diy.sh" "${WORK_PATH}/${CONFIG_REPO}" "${CONFIG_OWNER}" "${CONFIG_ARCH}"
 if [ $? -ne 0 ]; then
   echo "Failed to run diy.sh."
   exit 1
 else
   echo "Successfully updated diy.sh to run"
 fi
 
make toolchain/install
if [ $? -ne 0 ]; then
   echo "Failed to update to toolchain."
   exit 1
 else
   echo "Successfully updated to toolchain"
 fi

make defconfig

if [ "${GITHUB_ACTIONS}" = "true" ]; then
  echo "upload ${CONFIG_FILE}"
  pushd "${CONFIG_PATH}" || exit
  git pull
  cp -vf "${WORK_PATH}/${CONFIG_REPO}/.config" "${CONFIG_FILE}"
  status=$(git status -s | grep "${CONFIG_NAME}" | awk '{printf $2}')
  if [ -n "${status}" ]; then
    git add "${status}"
    git commit -m "update $(date +"%Y-%m-%d %H:%M:%S")"
    git push -f
  fi
  popd || exit # "${CONFIG_PATH}"
fi

echo "download package"
make download -j8 V=s

# find dl -size -1024c -exec ls -l {} \; -exec rm -f {} \;

echo "$(nproc) thread compile"
make -j"$(nproc)" V=s || make -j1 V=s
if [ $? -ne 0 ]; then
  echo "Build failed!"
  popd || exit # "${WORK_PATH}/${CONFIG_REPO}"
  exit 1
fi

pushd bin/targets/*/* || exit

ls -al

# sed -i '/buildinfo/d; /\.bin/d; /\.manifest/d' sha256sums
rm -rf packages *.buildinfo *.manifest *.bin sha256sums

rm -f *.img.gz
gzip -f *.img

mv -f *.img.gz "${WORK_PATH}"

popd || exit # bin/targets/*/*

popd || exit # "${WORK_PATH}/${CONFIG_REPO}"

du -chd1 "${WORK_PATH}/${CONFIG_REPO}"

echo "Done"
