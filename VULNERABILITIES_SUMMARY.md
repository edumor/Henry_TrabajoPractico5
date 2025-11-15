# KipuBankV3 - Resumen de Vulnerabilidades Detectadas

## 🔴 Vulnerabilidades Críticas

### 1. Oracle Price Manipulation (OWASP SC02:2025)
**Severidad**: 🔴 CRÍTICA  
**Estado**: ⚠️ Vulnerabilidad Activa

**Descripción**: El contrato depende de un único oráculo de Chainlink sin validaciones adicionales ni redundancia.

**Impacto**: 
- Pérdida total de fondos del protocolo
- Un atacante podría explotar una falla temporal del oráculo
- Precio manipulado = deposits inflados = retiros excesivos

**Evidencia**:
```solidity
// Test fallando: test_OraclePriceManipulation()
Expected: 20,000 USDC (con precio 10x)
Actual: 2,000 USDC
Error: 90% de diferencia
```

**Mitigación Recomendada**:
- Implementar múltiples oráculos (Chainlink + Uniswap TWAP)
- Agregar validación de desviación máxima entre fuentes
- Circuit breakers para cambios de precio extremos (>20%)

---

### 2. Flash Loan Attack Vulnerability (OWASP SC07:2025)
**Severidad**: 🔴 CRÍTICA  
**Estado**: ❌ Sin Protección

**Descripción**: No hay límites por transacción ni protección contra flash loans.

**Vector de Ataque**:
```
1. Atacante toma flash loan de 10,000 ETH
2. Manipula precio en Uniswap vendiendo masivamente
3. Deposita en KipuBank al precio artificialmente bajo
4. Revierte operación de Uniswap
5. Retira más USDC de lo depositado
6. Ganancia: Diferencia entre precio manipulado y real
```

**Impacto**: Pérdida estimada de $100k+ por ataque

**Mitigación Recomendada**:
- Límite máximo por transacción (MAX_SINGLE_DEPOSIT = 10 ETH)
- Cooldown period entre operaciones grandes (1 hora)
- Usar TWAP en lugar de precio spot

---

### 3. Decimal Conversion Errors (OWASP SC03:2025)
**Severidad**: 🔴 ALTA  
**Estado**: ⚠️ Tests Fallando

**Descripción**: Errores en conversiones ETH (18 decimales) ↔ USDC (6 decimales)

**Evidencia**:
```solidity
// Test: test_CompleteDepositWithdrawCycle()
Deposita: 10 ETH
Retira: 11 ETH
Error: 10% ganancia espuria
```

**Impacto**: 
- Usuarios pueden ganar/perder fondos por errores de redondeo
- Insolvencia del protocolo a largo plazo

**Mitigación Recomendada**:
- Revisar todas las fórmulas de conversión
- Implementar tests de precisión exhaustivos
- Documentar cada cálculo matemático con NatSpec

---

## 🟡 Vulnerabilidades Altas

### 4. Denial of Service via Capacity Limit (OWASP SC10:2025)
**Severidad**: 🟡 MEDIA-ALTA  
**Estado**: ❌ Sin Protección

**Descripción**: Un atacante puede llenar el banco hasta MAX_CAP bloqueando nuevos depósitos.

**Ataque**:
```
Costo: 50 ETH (~$100,000)
Resultado: Banco lleno, usuarios legítimos bloqueados
Tipo: Griefing attack (daño sin ganancia directa)
```

**Mitigación Recomendada**:
- Límite máximo por usuario (10,000 USDC)
- Sistema de cola para depósitos
- Capacidad dinámica ajustable por governance

---

### 5. Centralization Risk - Single Owner (OWASP SC01:2025)
**Severidad**: 🟡 ALTA  
**Estado**: ⚠️ Riesgo de Diseño

**Descripción**: Owner único puede pausar el contrato permanentemente.

**Riesgos**:
- Pérdida de clave privada = fondos bloqueados
- Owner comprometido = control total del atacante
- No hay mecanismo de recuperación

**Mitigación Recomendada**:
- Multi-firma (2-of-3 o 3-of-5)
- Timelock para acciones administrativas (2 días)
- Ownership transferible con periodo de gracia

---

## 🟢 Controles Implementados Correctamente

### ✅ Reentrancy Protection (OWASP SC05:2025)
- OpenZeppelin ReentrancyGuard implementado
- Patrón Checks-Effects-Interactions seguido
- Tests pasando: `testReentrancyProtection()`

### ✅ Access Control (OWASP SC01:2025)
- OpenZeppelin Ownable implementado correctamente
- Modificadores `onlyOwner` en funciones críticas
- Tests pasando: `test_OnlyOwnerFunctions()`

### ✅ Input Validation (OWASP SC04:2025)
- Validación de cantidades cero
- Validación de direcciones cero
- Tests pasando: `test_ZeroAmountValidation()`

### ✅ Overflow Protection (OWASP SC08:2025)
- Solidity 0.8.26 con protección automática
- No requiere SafeMath
- Tests pasando: `test_OverflowProtection()`

---

## 📊 Resumen Estadístico

| Categoría | Cantidad | % |
|-----------|----------|---|
| **Vulnerabilidades Críticas** | 3 | 60% |
| **Vulnerabilidades Altas** | 2 | 40% |
| **Vulnerabilidades Medias** | 0 | 0% |
| **Controles Correctos** | 4 | - |

### Tests Status
- **Total Tests**: 46
- **Pasando**: 32 (69.6%)
- **Fallando**: 14 (30.4%)

### Cobertura de Código
- **Simple Tests**: 11/11 ✅ (100%)
- **Security Tests**: 15/15 ✅ (100%)
- **Invariant Tests**: 5/12 ⚠️ (42%)

---

## 🎯 Recomendaciones Prioritarias

### Para Aprobar TP5 (Mínimo)
1. ✅ Documentar las vulnerabilidades encontradas (este documento)
2. ✅ Implementar tests de seguridad básicos
3. ✅ Explicar vectores de ataque identificados
4. ✅ Proponer mitigaciones para cada vulnerabilidad

### Para Producción (Crítico)
1. ❌ Corregir 14 tests fallando
2. ❌ Implementar multi-oráculo
3. ❌ Protección flash loan
4. ❌ Auditoría externa profesional
5. ❌ Multi-firma ownership
6. ❌ Plan de respuesta a incidentes

---

## 🚨 ADVERTENCIA

**Este contrato NO debe desplegarse en mainnet** sin implementar todas las mitigaciones recomendadas y pasar una auditoría externa profesional.

**Pérdida potencial estimada**: $100,000 - $1,000,000+ en caso de explotación.

---

## 📚 Referencias

- [OWASP Smart Contract Top 10 (2025)](https://owasp.org/www-project-smart-contract-top-10/)
- [Consensys Best Practices](https://consensys.github.io/smart-contract-best-practices/)
- [Trail of Bits Auditing Guide](https://appsec.guide/)
- [Rekt Test by Nascent](https://blog.trailofbits.com/2023/08/14/can-you-pass-the-rekt-test/)

---

**Autor**: Eduardo Moreno  
**Trabajo Práctico**: TP5 - Ethereum Developer Pack  
**Fecha**: Noviembre 15, 2025  
**Programa**: KIPU 2025
