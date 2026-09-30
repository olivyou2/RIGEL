# Scheduler ISA 명세

> 상태: 초안 + 15절의 첫 RTL 구현 프로파일  
> 범위: 커널 스케줄러 제어 프로세서 및 instruction stream  
> 명령어 폭: 32-bit fixed-width

## 1. 문서 규칙

이 문서는 대화에서 확정된 요구사항과 아직 결정되지 않은 사항을 명시적으로 구분한다.

- **확정(Required)**: RTL, assembler, reference model, 검증 환경이 동일하게 구현해야 하는 아키텍처 규칙이다.
- **TBD — Design Decision Needed**: 아직 확정되지 않았다. 구현자가 임의로 정한 값을 ISA 규칙으로 간주하면 안 된다.
- **구현 권고(Recommended)**: 확정 규칙을 만족하는 구현 방향이지만 ISA 보장은 아니다.

## 2. 설계 목적과 철학

### 2.1 스케줄러의 역할 — 확정

이 스케줄러는 가속기의 데이터 흐름을 지휘하는 작은 control processor다. 범용 CPU가 아니며, 가속기가 처리할 실제 payload를 GPR로 읽고 쓰거나 연산하지 않는다.

스케줄러의 역할은 다음과 같다.

1. 주소, 전송 길이, loop index/bound, stride, mask 및 기타 control/config 값을 계산한다.
2. unified register address space에 속한 special register를 통해 DMA 부가 파라미터를 설정한다.
3. `CPY`로 세 source DMA 중 하나를 fire한다.
4. `WAIT`로 DMA idle 상태와 동기화한다.
5. `EMIT`로 vector control word를 지정한 횟수만큼 직접 전송한다.
6. PC-relative conditional branch로 kernel control flow를 실행한다.

스케줄러 ISA에는 일반적인 데이터 메모리용 `LOAD`/`STORE`가 없다. GPR은 accelerator payload memory와 직접 통신하지 않는다. 실제 payload 이동은 DMA stream만 담당한다.

```text
Scheduler GPR / special register
        |
        | address, length, loop, control, configuration
        v
     CPY / WAIT  ---- control ----> source DMA0/1/2 ---> vector A/B/C
     EMIT        ---- write_req ----------------------> vector control
```

이 구분은 의도된 아키텍처 경계다. 스케줄러는 payload processor가 아니라 descriptor/control 계산기이자 dataflow orchestrator다.

## 3. 아키텍처 상태

### 3.1 Program Counter

- 모든 명령어는 32-bit fixed-width다.
- 순차 실행 시 다음 32-bit 명령어로 진행한다.
- 조건 분기의 target은 PC-relative다.
- PC의 단위와 branch offset scaling은 아직 TBD다.

### 3.2 Unified register address space — 확정

`rd`, `rs0`, `rs1`은 각각 5-bit다. 따라서 명령어가 접근하는 register address space는 총 32개 entry다.

이 주소 공간에는 다음이 함께 존재한다.

- 16개의 GPR;
- vector control 출력 주소 설정용 special register;
- 향후 확장을 위한 미사용/reserved entry.

모든 register operand는 동일한 5-bit namespace를 사용한다.

```text
read_register(5-bit addr)  -> GPR 또는 readable special register
write_register(5-bit addr) -> GPR 또는 writable special register
```

RTL 내부에서 GPR storage와 special-register storage를 물리적으로 분리하는 것은 허용된다. 단, software-visible decode와 접근 의미는 하나의 unified address space여야 한다.

16개 GPR과 special register의 정확한 numeric address map은 TBD다. 어떤 GPR도 현재 문서에서는 hardwired zero로 가정하지 않는다.

### 3.3 GPR 용도 — 확정

GPR은 다음 값을 보관하고 계산하기 위한 것이다.

- DMA source 시작 주소;
- DMA transfer length;
- loop index와 bound;
- address offset과 tile coordinate;
- vector control word와 출력 주소 설정값을 계산하기 위한 중간값;
- 기타 control/configuration 값.

GPR은 payload data cache가 아니다.

### 3.4 Special register 용도 — 확정 범위

Special register는 vector control stream의 출력 주소 시작점과 증가 간격을 제공한다.

의도된 역할 분리는 다음과 같다.

- 자주 바뀌는 source 시작 주소: `CPY.rs0`가 가리키는 register 값;
- 자주 바뀌는 transfer length: `CPY.rs1`이 가리키는 register 값;
- DMA 선택: `CPY.imm`;
- vector control 출력 주소의 base/step: special register.

Special-register 전체 목록, 주소, reset 값, access permission, per-DMA bank 구성은 TBD다.

## 4. 32-bit instruction format

### 4.1 Bit layout — 확정

모든 명령어는 하나의 고정 형식을 사용한다.

```text
 31          27 26 25          21 20          16 15          11 10           0
+--------------+--+--------------+--------------+--------------+--------------+
| opcode [4:0] |UI|   rd [4:0]   |  rs0 [4:0]  |  rs1 [4:0]  |  imm [10:0]  |
+--------------+--+--------------+--------------+--------------+--------------+
      5 bits    1       5 bits         5 bits         5 bits        11 bits
```

| Field | Width | 역할 |
|---|---:|---|
| `opcode` | 5 | instruction family 선택. Numeric opcode는 TBD. |
| `UI` (`Use Imm`) | 1 | ALU family에서 register form과 immediate form 선택. |
| `rd` | 5 | register write가 있는 명령어의 destination address. |
| `rs0` | 5 | 첫 번째 source register address. |
| `rs1` | 5 | 두 번째 source register address 또는 instruction-specific operand. |
| `imm` | 11 | immediate, branch displacement, DMA ID 등 instruction-specific 값. |

### 4.2 Use Imm 규칙 — ALU family에 대해 확정

`ADD(I)`, `MUL(I)`, `AND(I)`, `OR(I)`, `XOR(I)`, `SHL(I)`, `SHR(I)`는 opcode 하나와 `UI` bit를 공유하는 paired family다.

```text
UI = 0: operand1 = R[rs1]
UI = 1: operand1 = extend(imm)
```

`R[rs0]`는 첫 operand이며 결과는 `R[rd]`에 기록한다.

`extend(imm)`이 sign-extension인지 zero-extension인지는 아직 TBD다. Branch, `CPY`, `WAIT`에서 `UI`를 어떻게 사용하거나 어떤 canonical value로 제한할지도 TBD다.

### 4.3 Opcode — 미확정

명령어 이름과 의미는 확정되어 있으나 실제 5-bit opcode numeric value는 아직 할당되지 않았다. Decoder, assembler, disassembler, reference model은 추후 하나의 공용 opcode 정의를 사용해야 한다.

## 5. 명령어 요약

| Instruction | 결과 | 확정된 high-level 의미 |
|---|---|---|
| `ADD`, `ADDI` | `rd` | 덧셈 |
| `MUL`, `MULI` | `rd` | 곱셈 |
| `AND`, `ANDI` | `rd` | bitwise AND |
| `OR`, `ORI` | `rd` | bitwise OR |
| `XOR`, `XORI` | `rd` | bitwise XOR |
| `SHL`, `SHLI` | `rd` | left shift |
| `SHR`, `SHRI` | `rd` | right shift |
| `BEQ` | 없음 | equal이면 branch |
| `BNE` | 없음 | not equal이면 branch |
| `BGT` | 없음 | greater-than이면 branch |
| `BLT` | 없음 | less-than이면 branch |
| `CPY` | 없음 | `DMA#imm`를 fire하고 `R[rs0]`부터 `R[rs0]+R[rs1]` 범위의 데이터를 해당 DMA의 고정 ALU port로 stream |
| `WAIT` | 없음 | 선택된 DMA가 idle일 때까지 동기화 |
| `EMIT` | 없음 | `R[rs0]`의 raw control word를 `R[rs1]`회 vector control stream에 전송 |
| `HALT` | 없음 | 실행을 멈추고 host 명령을 받을 수 있는 idle 상태로 복귀 |

`CPY` range의 끝점 포함 여부는 아직 확정되지 않았다. 위 표의 “범위”는 수학적 inclusive/exclusive 표기를 의도하지 않는다.

## 6. ALU instruction semantics

아래 의사코드에서 `XLEN`은 register data width다. `XLEN` 자체는 TBD다.

### 6.1 ADD / ADDI

```text
operand1 = (UI == 1) ? extend(imm) : R[rs1]
R[rd]   = R[rs0] + operand1
```

Overflow 처리, flag 유무, immediate extension은 TBD다. 현재 확정된 architectural condition-code register는 없다.

### 6.2 MUL / MULI

```text
operand1 = (UI == 1) ? extend(imm) : R[rs1]
R[rd]   = R[rs0] * operand1
```

곱셈 signedness, 보존하는 product width, overflow/truncation 규칙은 TBD다.

### 6.3 AND / ANDI

```text
operand1 = (UI == 1) ? extend(imm) : R[rs1]
R[rd]   = R[rs0] & operand1
```

### 6.4 OR / ORI

```text
operand1 = (UI == 1) ? extend(imm) : R[rs1]
R[rd]   = R[rs0] | operand1
```

### 6.5 XOR / XORI

```text
operand1 = (UI == 1) ? extend(imm) : R[rs1]
R[rd]   = R[rs0] ^ operand1
```

### 6.6 SHL / SHLI

```text
shift_amount = (UI == 1) ? extend(imm) : R[rs1]
R[rd]        = R[rs0] << shift_amount
```

Legal shift range와 shift amount masking 규칙은 TBD다.

### 6.7 SHR / SHRI

```text
shift_amount = (UI == 1) ? extend(imm) : R[rs1]
R[rd]        = R[rs0] >> shift_amount
```

`SHR`가 logical shift인지 arithmetic shift인지는 TBD다. 두 종류가 모두 필요하다면 별도 encoding 규칙을 명시해야 한다.

## 7. Branch semantics

### 7.1 Branch condition — 연산 종류 확정, signedness 미확정

네 branch instruction은 모두 `R[rs0]`와 `R[rs1]`을 비교한다.

```text
BEQ: taken if R[rs0] == R[rs1]
BNE: taken if R[rs0] != R[rs1]
BGT: taken if R[rs0] >  R[rs1]
BLT: taken if R[rs0] <  R[rs1]
```

`BGT`와 `BLT`의 signed/unsigned 비교 규칙은 TBD다.

### 7.2 PC-relative target — 방식 확정, 세부 encoding 미확정

Taken branch의 target은 `imm`을 사용한 PC-relative 주소다.

```text
target_pc = branch_base_pc + extend_and_scale(imm)
```

다음 항목은 TBD다.

- 기준 PC가 branch instruction 자신의 주소인지 next sequential PC인지;
- offset 단위가 byte인지 32-bit instruction word인지;
- branch immediate가 signed인지와 정확한 extension 방식.

Not-taken branch는 다음 순차 명령어로 진행한다.

### 7.3 Redirect priority와 허용 penalty — 확정

Branch redirect는 fetch output의 `requestable`과 독립적인 high-priority control event다.

필수 동작은 다음과 같다.

1. 기존 fetch request가 backpressure로 막혀 있어도 taken branch는 fetch의 architectural PC와 epoch을 즉시 갱신한다.
2. 이미 `valid=1`로 제시된 stalled fetch request의 address, epoch, 기타 payload는 handshake까지 유지한다. Redirect 때문에 payload를 덮어쓰지 않는다.
3. Branch가 발생한 cycle에는 target에 대한 새 fetch를 발행하지 않는다.
4. 다음 cycle부터 target fetch를 발행할 수 있다. 단순한 control을 위해 redirect 1-cycle penalty를 허용한다.
5. 이미 발행된 old-path request는 old epoch 상태로 나중에 handshake/응답할 수 있으며, 이후 epoch filter가 stale token으로 폐기한다.

개념적인 우선순위는 다음과 같다.

```text
1. reset
2. 기존 fetch handshake bookkeeping
3. branch redirect: PC/epoch update
4. otherwise, enable && requestable이면 normal fetch issue
```

2와 3이 독립 state를 갱신한다면 같은 edge에서 처리할 수 있다. 핵심은 redirect가 normal issue보다 우선한다는 것이다.

## 8. DMA와 고정 ALU port 구조

### 8.1 세 source DMA와 직접 control stream — 현재 구현

현재 scheduler가 fire하는 DMA는 세 개다. DMA0/1/2는 각각 vector A/B/C source stream port에 고정 연결된다. 별도의 opcode/control stream은 scheduler의 `vector_control_req` ready/valid 출력이 직접 만든다.

그 결과:

- `CPY`는 runtime destination port가 아니라 세 source DMA 중 하나를 선택한다.
- Destination ALU port는 DMA ID로 암시된다.
- Instruction에 별도의 destination-port operand가 필요 없다.
- Software와 RTL은 동일한 고정 `DMA ID -> ALU port` mapping을 공유해야 한다.

```text
DMA0 -> vector A stream
DMA1 -> vector B stream
DMA2 -> vector C stream
EMIT -> vector control stream
```

각 ALU port의 실제 이름과 top-level interface 이름은 TBD다.

### 8.2 CPY — 핵심 semantics 확정

`CPY`는 `DMA#imm`를 fire한다. 현재 legal DMA ID는 0, 1, 2이다.

```text
dma_id       = imm
source_start = R[rs0]
length       = R[rs1]

fire DMA[dma_id]
stream payload beginning at source_start
toward the fixed ALU port connected to DMA[dma_id]
```

의도된 source 범위는 다음과 같이 표현된다.

```text
R[rs0] 부터 R[rs0] + R[rs1] 까지
```

단, 끝 주소가 inclusive인지, 일반적인 `[source_start, source_start + length)` half-open range인지는 아직 결정되지 않았다.

`CPY`에는 explicit destination address나 destination port가 없다. DMA ID가 해당 DMA에 고정된 ALU port를 암시한다.

자주 바뀌는 두 값은 operand로 직접 전달한다.

- `R[rs0]`: source 시작 주소;
- `R[rs1]`: length.

세 DMA의 step은 source beat 크기로 고정된다. Destination address는 각각의 고정 stream port에서 사용하지 않는다.

다음 `CPY` 세부사항은 TBD다.

- 11-bit `imm`에서 DMA ID 0, 1, 2의 정확한 canonical encoding;
- unsupported DMA ID의 동작;
- source range 끝점의 inclusive/exclusive convention;
- length의 단위(byte, beat, element 등);
- address와 length alignment 요구사항;
- zero-length transfer 동작;
- busy DMA에 `CPY`를 실행했을 때 wait, reject, fault 중 어떤 동작인지;
- fire 시점에 descriptor/config를 atomic snapshot하는지;
- 사용하지 않는 `rd`, `UI` field의 canonical value;
- `CPY`가 architectural single-cycle인지, fire acceptance까지 multi-cycle일 수 있는지.

### 8.3 WAIT — 목적 확정, operand encoding 미확정

`WAIT`는 DMA idle 상태와 동기화한다.

```text
if selected DMA idle condition is false:
    WAIT에서 scheduler 진행을 정지
else:
    다음 instruction으로 진행
```

`WAIT` 자체는 payload를 이동하지 않는다.

아직 결정해야 할 operand encoding 후보는 다음과 같다.

- immediate DMA ID 하나;
- register value로 지정한 DMA ID 하나;
- immediate 또는 register bitmask로 지정한 DMA 집합;
- 별도로 정의할 다른 방식.

`idle`의 정확한 완료 경계도 TBD다. 예를 들어 request accept, source read 완료, 마지막 stream beat의 ALU-port handshake, 또는 모든 downstream effect 완료 중 어느 시점을 의미하는지 결정해야 한다.

### 8.4 EMIT — 직접 vector control stream

`EMIT rs0, rs1`은 `R[rs0][15:0]`을 raw control word로, `R[rs1]`을 전송 횟수로 사용한다. 출력 주소는 special register `OUTPUT_BASE`(address 16)에서 시작하여 각 handshake마다 `OUTPUT_STEP`(address 17)을 더한다. Control word와 base/step/count는 명령을 decode할 때 snapshot한다.

```text
for i in 0 .. R[rs1]-1:
    vector_control_req.data = zero_extend(R[rs0][15:0])
    vector_control_req.addr = OUTPUT_BASE + i * OUTPUT_STEP
    wait until vector_control_req.valid && vector_control_req.ready
```

`R[rs1]=0`이면 아무 beat도 전송하지 않는다. `EMIT`는 모든 beat가 수락될 때까지 scheduler instruction 진행을 막는다. `valid && !ready` 동안 word와 address를 유지한다.

16-bit raw control layout은 `[0]=lane_sel`, `[5:1]=vector ALU opcode`, `[6]=accumulate`, `[7]=reduce(미구현)`, `[9:8]=sat_mode`, `[15:10]=예약`이다. `sat_mode=00`은 하위 8비트 wrap, `01`은 signed int8 saturation(-128..127), `10`은 unsigned int8 saturation(0..255), `11`은 예약이며 현재 wrap으로 처리한다. Control은 A/B/C와 함께 ALU join에 들어가며 ALU 결과와 함께 accumulator로 전달된다. `[6]=1`인 beat는 signed 32비트 lane별로 누산만 하고 출력하지 않는다. `[6]=0`인 beat는 이 beat의 signed 16비트 ALU 결과까지 더한 뒤 sat_mode에 따라 8비트로 출력하고 lane별 누산 상태를 지운다. Vector opcode 0–11은 B/C를 사용하고 A를 무시하며, opcode 12는 lane별 signed `A + B*C`다. 현재 scratchpad 결과는 8비트/lane이므로 int32 부분합을 메모리에 보존할 수 없고, K 방향 누산은 최종 flush 전까지 accumulator 안에서 완료해야 한다.

## 9. Programming model 예시

아래 코드는 symbolic assembly 예시다.

```text
# GPR로 source와 length 계산
ADDI  r_src, r_base, tile_offset
MULI  r_len, r_width, element_size

# vector 결과 주소와 raw control word 설정
ADDI  OUTPUT_BASE, r_zero_value, 256
ADDI  OUTPUT_STEP, r_zero_value, 16
ADDI  r_ctrl, r_zero_value, 6     # AND opcode=3, lane_sel=0
ADDI  r_count, r_zero_value, 4

# DMA ID는 immediate, destination은 DMA0의 고정 ALU port
CPY   dma=0, src=r_src, length=r_len
CPY   dma=1, src=r_src_b, length=r_len
EMIT  r_ctrl, r_count

# DMA가 일하는 동안 다음 control state 계산 가능
ADDI  r_tile, r_tile, 1

# 의존 상태를 재사용하기 전에 동기화
WAIT  dma=0
WAIT  dma=1

BNE   r_tile, r_limit, loop
```

`r_zero_value`는 단지 값 0을 보유한 일반 register를 뜻한다. Hardwired zero register가 확정되었다는 의미가 아니다.

## 10. Ready/valid stream 계약

### 10.1 기본 handshake — 확정

Scheduler instruction stream channel은 ready/valid 의미론을 따른다.

```text
handshake = valid && ready
```

Producer의 필수 규칙:

- `valid`를 assert한 뒤 `valid && !ready`인 동안 payload를 안정적으로 유지한다.
- Transfer는 handshake에서만 발생한다.
- 이미 제시된 stalled token을 branch redirect 때문에 덮어쓰지 않는다.

Registered output stage는 다음 조건으로 output entry가 새 값을 받을 수 있는지 계산할 수 있다.

```text
requestable = !out.valid || out.ready
```

### 10.2 Epoch metadata — 철학과 필수 결과 확정

Instruction fetch request/response token은 epoch metadata를 운반한다. Epoch은 token이 속한 control-flow generation을 나타낸다.

필수 원칙:

- 새 fetch에는 current epoch을 붙인다.
- Redirect는 PC와 current epoch을 갱신한다.
- 이미 발행한 request를 epoch 변경만으로 물리적으로 취소하지 않는다.
- Token epoch이 current epoch과 다르면 stale이다.
- Stale token은 architectural side effect를 만들기 전에 consume/drop한다.
- 모든 stage에 무조건 filter를 넣는 대신, 최소한 side-effect boundary에는 epoch check를 둔다.

Epoch width, reset value, owner/increment 방식, wraparound 안전 규칙은 TBD다. 유한 epoch counter가 wrap하여 오래 정체된 stale token과 다시 같은 값이 되는 ABA 문제를 반드시 해결해야 한다.

### 10.3 Redirect feedback path — 확정 범위

Branch-resolution 지점에서 fetch로 돌아가는 redirect 정보는 forward instruction stream과 별개의 control feedback path다.

Redirect는 normal fetch issue보다 우선하며 fetch output backpressure 때문에 유실되면 안 된다.

Redirect message가 `{target_pc, target_epoch}`을 전달할지, `target_pc`만 보내고 fetch가 epoch을 증가시킬지는 TBD다. 어느 구현이든 7.3절의 externally observable behavior는 동일해야 한다.

## 11. `sch_epoch_filter` 계약

### 11.1 구조 — 확정

논의된 `sch_epoch_filter`는 registered-ready를 사용하는 2-entry elastic epoch filter다.

```text
upstream -> [output entry] -> downstream
                 ^
                 |
             [skid entry]
```

저장 용량은 다음과 같다.

- output entry 한 개;
- skid entry 한 개;
- 최대 두 개의 live/current-epoch token.

`upstream.ready`를 register로 관리하여 `downstream.ready -> upstream.ready` combinational path를 피하는 것이 의도다.

### 11.2 Stale token 처리 — 확정

Upstream token은 `upstream.valid && upstream.ready`에서 accept된다.

- Epoch이 current epoch과 같고 output entry가 받을 수 있으면 output에 저장한다.
- Epoch이 같고 output이 막혀 있으며 skid가 비어 있으면 skid에 저장하고 upstream backpressure를 건다.
- Epoch이 stale이면 consume/drop하고 저장하지 않는다. 따라서 stale token은 두 entry의 live-token capacity를 소비하지 않는다.

Skid entry를 drain할 때는 **그 시점의 current epoch과 다시 비교**해야 한다. Skid에 들어갈 때 match였다는 사실만으로 forward하면 안 된다. Stall 중 epoch이 바뀔 수 있기 때문이다.

Reset은 `downstream.valid`와 `skid.valid`를 모두 clear해야 한다. Reset 후 input은 합의된 RTL reset convention에 따라 accept 가능한 상태가 되어야 한다.

### 11.3 Occupancy invariant — 확정 의도

정상적인 stable state는 다음 관계를 만족한다.

| Output valid | Skid valid | Upstream ready | 의미 |
|---:|---:|---:|---|
| 0 | 0 | 1 | empty |
| 1 | 0 | 1 | 한 token 저장, 한 token 추가 accept 가능 |
| 1 | 1 | 0 | full, live input에 backpressure |

그 밖의 조합은 assertion으로 금지하거나 RTL에서 발생 가능한 transient라면 근거를 문서화해야 한다.

### 11.4 Throughput과 recovery bubble — 확정

Downstream이 계속 ready이고 stale interruption이 없다면 peak steady-state throughput은 **1 token/cycle**이다.

Full 상태의 skid를 drain하는 cycle에는 직전 cycle까지 registered `upstream.ready=0`이므로 새 upstream token을 동시에 accept할 수 없다. 따라서 다음과 같은 1-cycle recovery bubble이 생길 수 있다.

```text
... A -> B -> [bubble] -> C ...
```

이 trade-off는 허용한다. Scheduler에서는 bubble 제거보다 단순한 registered timing, 명확한 handshake, 2-entry capacity를 우선한다.

### 11.5 Epoch 변경 시 이미 stalled된 output — TBD

검토된 RTL은 skid token을 drain할 때 epoch을 재검사한다. 그러나 이미 `downstream.valid && !downstream.ready`로 제시된 output token이 stall 중 stale이 되었을 때 filter 자체가 어떻게 처리할지는 확정되지 않았다.

이 결정 전까지 integration은 token epoch을 보존하고, downstream epoch check 또는 commit check를 통해 stale output이 side effect를 일으키지 않음을 보장해야 한다. Filter가 stalled output의 `valid`를 직접 취소할 수 있는지 여부는 ready/valid payload-stability 계약과 함께 확정해야 한다.

## 12. 검증 요구사항

### 12.1 Decode와 register access

- 모든 ALU family의 `UI=0`, `UI=1` form;
- GPR 및 구현된 special-register address에 대한 unified read/write;
- reserved/unimplemented register address 동작;
- signedness 확정 후 equal/boundary value에서 모든 branch condition.

### 12.2 DMA control

- 세 legal DMA ID 각각이 자신의 고정 ALU port로 연결되는지;
- `CPY`가 `R[rs0]`를 source start, `R[rs1]`를 length로 쓰는지;
- OUTPUT_BASE/OUTPUT_STEP 설정이 `EMIT` 주소에 반영되는지;
- raw control word가 지정된 횟수만큼, stall 중 안정적으로 전송되는지;
- `WAIT`가 정의된 idle event까지 막히고 이후 정확히 한 번 진행하는지;
- 결정 완료 후 zero length, misalignment, busy-DMA fire, illegal DMA ID 동작.

### 12.3 Branch, epoch, fetch

- taken/not-taken PC-relative branch;
- fetch output이 empty일 때 redirect;
- old fetch request가 `valid && !ready`일 때 redirect;
- stalled old request payload가 handshake까지 안정적인지;
- `requestable=0`이어도 PC/epoch이 갱신되는지;
- branch cycle에 target request를 내보내지 않는지;
- 다음 cycle에 target fetch가 가능해지는지;
- old-epoch response가 drop되는지;
- stale instruction이 GPR/special register write, DMA fire 등 side effect를 만들지 않는지.

### 12.4 Epoch filter

- reset 시 output/skid valid clear;
- current-epoch token pass;
- output empty에서 stale input consume/drop;
- output blocked, skid empty에서 stale input consume/drop;
- output blocked에서 current token을 skid에 저장;
- 두 entry full일 때 backpressure;
- token이 skid에 있는 동안 epoch 변경 후 drain 시 drop;
- downstream handshake와 같은 cycle의 output replacement;
- steady-state 1 token/cycle;
- skid drain 뒤 허용된 1-cycle recovery bubble;
- epoch policy 확정 후 wraparound/ABA safety.

권장 assertion에는 stall 중 payload stability, full skid overwrite 금지, stale epoch side effect 금지, legal occupancy 조합, 고정 DMA-to-port binding을 포함한다.

## 13. 설계 결정 추적표 (초안 기준)

다음 항목은 초안 작성 시점의 미결정 목록이다. 첫 RTL 구현에서 정한 값은 15절에 기록하며, 15절이 해당 항목에 우선한다. 15절에서 다루지 않은 항목은 여전히 미결정이다.

| ID | 미확정 항목 | 영향 범위 |
|---|---|---|
| DDN-001 | 각 instruction family의 5-bit numeric opcode | ISA package, decoder, assembler |
| DDN-002 | Register width (`XLEN`) | register file, ALU, DMA address/length interface |
| DDN-003 | vector control output base/step을 포함한 special-register address map | decoder, register file, EMIT |
| DDN-004 | Register reset value, R/W permission, unimplemented address 동작 | RTL, software model |
| DDN-005 | Hardwired zero GPR 존재 여부 | register file, assembler convention |
| DDN-006 | 각 ALU immediate의 sign/zero extension 규칙 | decoder, ALU, assembler |
| DDN-007 | Arithmetic signedness, multiply result width, overflow/truncation | ALU |
| DDN-008 | `SHR`의 logical/arithmetic 의미와 shift amount masking | ALU |
| DDN-009 | `BGT`/`BLT` signed/unsigned 비교 | branch unit |
| DDN-010 | Branch base PC, displacement signedness, byte/word scaling | assembler, branch unit, fetch |
| DDN-011 | `CPY` source range 끝점의 inclusive/exclusive convention | DMA, assembler, reference model |
| DDN-012 | `CPY` length 단위, alignment, zero length, busy/illegal-ID 동작 | DMA control |
| DDN-013 | Non-ALU instruction의 unused `rd`/`UI` canonical value | decoder, assembler |
| DDN-014 | `WAIT` operand encoding과 single-DMA/mask 의미 | decoder, control unit |
| DDN-015 | `WAIT`가 관찰하는 DMA `idle`의 정확한 완료 경계 | DMA, scheduler control |
| DDN-016 | DMA fire acceptance protocol과 `CPY` multi-cycle 허용 여부 | scheduler/DMA interface |
| DDN-017 | 세 source DMA port와 직접 control port의 logical/physical 이름 | top-level integration |
| DDN-018 | Epoch width, owner/increment protocol, reset, wraparound 보호 | fetch, redirect, filters |
| DDN-019 | Branch-resolution stage와 redirect channel transport | pipeline control |
| DDN-020 | Epoch 변경으로 stale이 된 stalled filter output의 처리 | `sch_epoch_filter`, downstream filter |
| DDN-021 | Illegal/reserved instruction 동작과 fault/report 방식 | decoder, control/status |
| DDN-022 | Program 종료 방식 (`HALT`, host stop, end PC 등) | ISA, scheduler control |

## 14. 구현 인계 체크리스트

RTL interface를 freeze하기 전에 최소한 DDN-001, DDN-002, DDN-003, DDN-006~016, DDN-018, DDN-020을 닫아야 한다. 이들은 binary compatibility 또는 functional correctness에 직접 영향을 준다.

첫 구현은 다음 비협상 요구사항을 보존해야 한다.

1. `opcode 5b + UI 1b + rd 5b + rs0 5b + rs1 5b + imm 11b`의 32-bit fixed format.
2. Unified 5-bit GPR/special-register address space 안의 16개 GPR.
3. Scheduler payload-memory `LOAD`/`STORE` 경로 없음.
4. `CPY`는 세 source `DMA#imm` 중 하나를 선택하고 `R[rs0]`를 source start, `R[rs1]`를 length로 사용한다.
5. `EMIT`는 raw vector control word를 지정한 횟수만큼 직접 stream에 전송한다. OUTPUT_BASE/OUTPUT_STEP은 special register로 제공한다.
6. `WAIT`는 source DMA idle과 동기화.
7. Branch target은 PC-relative.
8. Redirect는 fetch backpressure와 독립적으로 PC/epoch을 갱신하고, redirect cycle에는 새 fetch를 발행하지 않으며 1-cycle penalty를 허용.
9. Stalled ready/valid transaction의 payload stability 보장.
10. Epoch metadata로 old-path token을 무효화하되 모든 in-flight transaction의 물리적 취소를 요구하지 않음.
11. `sch_epoch_filter`는 output+skid의 두 live-token capacity를 제공하고, stale input을 drop하며, skid drain 시 epoch을 재검사하고, peak steady-state 1 token/cycle을 유지하되 skid recovery bubble은 허용.

## 15. 첫 RTL 구현 프로파일

이 절은 `sch.sv`/`sch_execute.sv`에서 실제 선택한 규칙이다. 기존 초안의 TBD 중 아래에 해당하는 항목을 닫는다.

### 15.1 Opcode와 register map

| Opcode | 명령 | Opcode | 명령 |
|---:|---|---:|---|
| 0 | ADD(I) | 1 | MUL(I) |
| 2 | AND(I) | 3 | OR(I) |
| 4 | XOR(I) | 5 | SHL(I) |
| 6 | SHR(I) | 7 | BEQ |
| 8 | BNE | 9 | BGT |
| 10 | BLT | 11 | CPY |
| 12 | WAIT | 13 | EMIT |
| 14 | HALT | 15–31 | illegal |

- XLEN은 32비트다. `r0`부터 `r15`까지는 reset 값이 0인 일반 GPR이며, `r0`도 쓸 수 있다.
- Register address 16은 `OUTPUT_BASE`, 17은 `OUTPUT_STEP`이다. 둘 다 ALU 명령의 `rd`로 설정하고 source operand로 읽을 수 있다.
- 18–31의 read 값은 0이며, 해당 주소에 쓰는 명령은 `fault`를 발생시킨다.
- `OUTPUT_STEP`의 reset 값은 `SRC_DMA_BEAT_BYTES`(기본 16); `OUTPUT_BASE`의 reset 값은 0이다.
- ADD/MUL immediate는 11비트 signed 확장, bitwise immediate는 zero 확장이다. 결과는 하위 32비트만 보존한다.
- shift amount는 레지스터형과 immediate형 모두 하위 5비트만 사용한다. SHR은 logical right shift다.
- BGT/BLT는 signed 비교다. Branch target은 `branch instruction PC + sign_extend(imm) × 4`이다.
- Non-ALU instruction에서 UI와 사용하지 않는 rd 필드는 현재 decoder가 무시한다. Assembler는 0으로 encoding한다.

### 15.2 DMA 명령

- `CPY`와 `WAIT`는 `imm` 전체를 DMA ID로 사용한다. `0`, `1`, `2`만 legal이며 다른 값은 `fault`다.
- DMA0/1/2는 각각 A/B/C의 고정 stream port로 간다. `addr_dst=0`, `step=SRC_DMA_BEAT_BYTES`(기본 16)로 연결하며 scheduler가 설정 register를 제공하지 않는다.
- Opcode/control stream은 DMA가 아니라 scheduler의 `vector_control_req` 출력이다.
- `CPY`는 `addr_src=R[rs0]`, `length=R[rs1]`을 전달한다. Descriptor는 execute entry에 보관되며 `dma_ctrl.valid && dma_ctrl.ready`에서 정확히 한 번 fire한다. Busy DMA에는 ready가 돌아올 때까지 기다린다.
- `WAIT`는 선택한 DMA의 `dma_ctrl.ready`가 1이 될 때 retire한다. 현재 `dma_control.sv`에서 ready는 issue와 dataout FSM이 모두 idle인 상태다.
- Length는 byte 단위이고 범위는 `[addr_src, addr_src + length)`이다. 기존 DMA는 zero length 또는 zero step descriptor를 받아 no-op 처리한다. 실제 이동은 beat 단위이므로 length/step 정렬 검사는 소프트웨어 책임으로 둔다.
- `EMIT rs0, rs1`은 `R[rs0][15:0]`을 raw control word로, `R[rs1]`을 beat 수로 사용한다. `OUTPUT_BASE`부터 시작하고 매 accepted beat마다 `OUTPUT_STEP`을 더한다. Word/count/base/step은 decode 시 snapshot하며 마지막 beat가 handshake된 뒤 retire한다.

### 15.3 Epoch 및 종료

- Fetch가 4비트 epoch를 소유하고 taken branch마다 1 증가시킨다. Execute/commit은 token epoch가 현재 epoch와 같을 때만 register write, DMA fire, branch redirect를 수행한다.
- `sch_epoch_filter`가 이미 downstream에 제시한 stalled token은 강제로 취소하지 않는다. Side-effect boundary인 execute/commit이 stale token을 drop한다.
- `HALT`(opcode 14)는 정상적으로 실행을 끝내고 scheduler를 idle로 돌린다. Illegal instruction은 sticky `fault`를 세우고 scheduler를 idle로 돌린다. 다음 유효한 FIRE는 execution fault를 clear한다.
- 4비트 epoch가 16회 redirect 후 재사용될 때 오래 남은 응답과 충돌하는 ABA 문제는 아직 해결하지 않았다. 이 프로파일을 사용하는 instruction-memory 경로는 응답이 그 기간보다 오래 남지 않도록 보장해야 한다. 일반적인 unbounded-latency memory와 연결하려면 outstanding epoch 추적 또는 더 큰 epoch/재사용 방지 장치가 필요하다.
- Instruction memory는 request의 `addr`와 `epoch`를 response에 그대로 되돌려야 하며, response 순서를 request 순서대로 유지해야 한다.

### 15.4 Host `write_req`와 FIRE

Scheduler는 reset 뒤 idle이다. `running=0`인 동안만 `write_req.ready=1`이며, 실행 중에는 host write에 backpressure를 건다. `write_req`는 `rv_if` ready/valid write channel이고, 아래 주소는 scheduler의 local byte offset이다. 쓰기 데이터의 하위 32비트만 사용한다. `vector_system`의 IXC는 `addr[19:18]=2`로 scheduler를 선택하고 원래 주소를 그대로 전달하므로, 외부 host 주소는 `0x80000 + local offset`이다. Scheduler는 `write_req.addr[17:0]`을 decode한다.

| `write_req.addr` | 동작 |
|---:|---|
| `0x00`–`0x3c`, 4-byte 간격 | `r0`–`r15` 쓰기 |
| `0x40` | `OUTPUT_BASE`(register 16) 쓰기 |
| `0x44` | `OUTPUT_STEP`(register 17) 쓰기 |
| `0x80` | FIRE: `write_req.data[31:0]`을 시작 byte PC로 설정하고 실행 시작 |

FIRE의 PC는 4-byte aligned여야 한다. 다른 offset 또는 misaligned FIRE는 수락하되 `fault`를 세우며 실행을 시작하지 않는다. 다음 유효한 FIRE는 host fault를 clear한다. FIRE는 fetch PC를 설정하고 epoch를 증가시켜 이전 실행의 늦은 instruction response를 stale로 만든다. 이미 backpressure 중인 fetch request는 handshake 전까지 payload를 유지한다.
