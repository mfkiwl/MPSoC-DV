/*
 * Copyright 2020 Google LLC
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

`DEFINE_C_INSTR(C_LW,       CL_FORMAT, LOAD, OMSP32C, UIMM)
`DEFINE_C_INSTR(C_SW,       CS_FORMAT, STORE, OMSP32C, UIMM)
`DEFINE_C_INSTR(C_LWSP,     CI_FORMAT, LOAD, OMSP32C, UIMM)
`DEFINE_C_INSTR(C_SWSP,     CSS_FORMAT, STORE, OMSP32C, UIMM)
`DEFINE_C_INSTR(C_ADDI4SPN, CIW_FORMAT, ARITHMETIC, OMSP32C, NZUIMM)
`DEFINE_C_INSTR(C_ADDI,     CI_FORMAT, ARITHMETIC, OMSP32C, NZIMM)
`DEFINE_C_INSTR(C_ADDI16SP, CI_FORMAT, ARITHMETIC, OMSP32C, NZIMM)
`DEFINE_C_INSTR(C_LI,       CI_FORMAT, ARITHMETIC, OMSP32C)
`DEFINE_C_INSTR(C_LUI,      CI_FORMAT, ARITHMETIC, OMSP32C, NZIMM)
`DEFINE_C_INSTR(C_SUB,      CA_FORMAT, ARITHMETIC, OMSP32C)
`DEFINE_C_INSTR(C_ADD,      CR_FORMAT, ARITHMETIC, OMSP32C)
`DEFINE_C_INSTR(C_NOP,      CI_FORMAT, ARITHMETIC, OMSP32C)
`DEFINE_C_INSTR(C_MV,       CR_FORMAT, ARITHMETIC, OMSP32C)
`DEFINE_C_INSTR(C_ANDI,     CB_FORMAT, LOGICAL, OMSP32C)
`DEFINE_C_INSTR(C_XOR,      CA_FORMAT, LOGICAL, OMSP32C)
`DEFINE_C_INSTR(C_OR,       CA_FORMAT, LOGICAL, OMSP32C)
`DEFINE_C_INSTR(C_AND,      CA_FORMAT, LOGICAL, OMSP32C)
`DEFINE_C_INSTR(C_BEQZ,     CB_FORMAT, BRANCH, OMSP32C)
`DEFINE_C_INSTR(C_BNEZ,     CB_FORMAT, BRANCH, OMSP32C)
`DEFINE_C_INSTR(C_SRLI,     CB_FORMAT, SHIFT, OMSP32C, NZUIMM)
`DEFINE_C_INSTR(C_SRAI,     CB_FORMAT, SHIFT, OMSP32C, NZUIMM)
`DEFINE_C_INSTR(C_SLLI,     CI_FORMAT, SHIFT, OMSP32C, NZUIMM)
`DEFINE_C_INSTR(C_J,        CJ_FORMAT, JUMP, OMSP32C)
`DEFINE_C_INSTR(C_JAL,      CJ_FORMAT, JUMP, OMSP32C)
`DEFINE_C_INSTR(C_JR,       CR_FORMAT, JUMP, OMSP32C)
`DEFINE_C_INSTR(C_JALR,     CR_FORMAT, JUMP, OMSP32C)
`DEFINE_C_INSTR(C_EBREAK,   CI_FORMAT, SYSTEM, OMSP32C)