#!/usr/bin/env bash
# Copyright 2018, Logan Vig <logan2211@gmail.com>
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -e -u -x
set -o pipefail

. $(dirname $(readlink -f "$0"))/functions.sh

if [ -z "${ANSIBLE_INVENTORY+undefined}" ] && [ -z "${TEST_INVENTORY+undefined}" ]; then
    echo "ERROR: Set a test inventory in TEST_INVENTORY environment variable"
    exit 1
else
    export ANSIBLE_INVENTORY="${TESTS_PATH}/${TEST_INVENTORY}"
fi

bootstrap_system

source $ANSIBLE_VENV_PATH/bin/activate

cd $PROJECT_PATH
run_ansible get-ansible-role-requirements.yml
run_ansible get-ansible-collection-requirements.yml

# Use the cloned roles
export ANSIBLE_ROLES_PATH="${PROJECT_PATH}/roles:${PROJECT_PATH}/ephemeral_roles"
# Use project's collections
export ANSIBLE_COLLECTIONS_PATHS="${PROJECT_PATH}/collections"

run_ansible tests/test.yml
