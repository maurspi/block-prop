// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

// ─────────────────────────────────────────────────────────────────
//  Interfaces externas
// ─────────────────────────────────────────────────────────────────

/// @dev Interfaz mínima de Chainlink AggregatorV3 para el oráculo ICL
interface IICLOracle {
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,   // índice ICL × 1e8
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}

/// @dev Interfaz mínima ERC-20 para pagos en stablecoin (ej. USDT en Polygon)
interface IERC20 {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address account) external view returns (uint256);
}

// ─────────────────────────────────────────────────────────────────
//  Contrato principal
// ─────────────────────────────────────────────────────────────────

/**
 * @title  ContratoAlquiler
 * @notice Contrato inteligente de locación residencial sobre Polygon.
 *         Implementa las 5 funcionalidades del canvas:
 *           1. Depósito en escrow automático
 *           2. Pago mensual con penalidad por mora
 *           3. Actualización de precio indexada por oráculo ICL
 *           4. Registro de incidencias on-chain
 *           5. Cláusula de rescisión anticipada programable
 * @dev    Desplegado por el escribano; requiere firma de propietario
 *         e inquilino antes de activarse.
 */
contract ContratoAlquiler {

    // ─── Enumeraciones ───────────────────────────────────────────

    enum Estado {
        PENDIENTE_FIRMAS,   // esperando que ambas partes firmen
        ACTIVO,             // contrato en curso
        EN_DISPUTA,         // depósito bloqueado por árbitro
        FINALIZADO,         // vencimiento normal
        RESCINDIDO          // terminación anticipada
    }

    enum EstadoPago {
        AL_DIA,
        EN_MORA,
        IMPAGO               // mora > 3 meses → habilita resolución
    }

    // ─── Estructuras ─────────────────────────────────────────────

    struct Incidencia {
        uint256 id;
        address reportadaPor;
        string  descripcion;
        uint256 timestamp;
        bool    resuelta;
        bool    descontadaDeAlquiler;
    }

    struct PeriodoPago {
        uint256 mes;           // timestamp del primer día del mes
        uint256 montoBase;     // monto al momento del vencimiento
        uint256 montoAbonado;
        uint256 fechaPago;
        bool    ajustadoICL;
    }

    // ─── Variables de estado ─────────────────────────────────────

    // Partes
    address public propietario;
    address public inquilino;
    address public escribano;          // árbitro y validador notarial
    address public arbiter;            // puede ser igual al escribano

    // Token de pago
    IERC20  public tokenPago;          // stablecoin (ej. USDT)

    // Oráculo
    IICLOracle public oracleICL;
    int256  public iclBaseIndex;       // índice ICL al inicio del contrato × 1e8
    uint256 public proximoAjuste;      // timestamp del próximo ajuste trimestral

    // Condiciones económicas
    uint256 public alquilerMensual;    // en wei del token (6 decimales USDT)
    uint256 public deposito;           // 2 meses de alquiler
    uint256 public tasaMoraDiaria;     // en basis points (335 = 3.35%)
    uint256 public mesesMultaRescision;// meses de multa por salida anticipada

    // Duración
    uint256 public fechaInicio;
    uint256 public fechaFin;
    uint256 public diaVencimientoPago; // día del mes (ej. 1)

    // Estado del contrato
    Estado      public estado;
    EstadoPago  public estadoPago;

    // Firmas
    bool public firmadoPropietario;
    bool public firmadoInquilino;
    bool public avalNotarial;

    // Incidencias
    uint256                      public contadorIncidencias;
    mapping(uint256 => Incidencia) public incidencias;
    uint256 public plazoRespuestaPropietario = 10 days;

    // Pagos
    uint256                          public periodoActual;
    mapping(uint256 => PeriodoPago)  public periodos;
    uint256 public ultimoPago;

    // Escrow
    uint256 public depositoBloqueado;

    // ─── Eventos ─────────────────────────────────────────────────

    event ContratoActivado(uint256 fechaInicio, uint256 fechaFin);
    event PagoRecibido(uint256 periodo, uint256 monto, uint256 timestamp);
    event MoraAplicada(uint256 periodo, uint256 interesPunitorio, uint256 diasMora);
    event AlquilerAjustado(uint256 montoAnterior, uint256 montoNuevo, int256 iclActual);
    event IncidenciaRegistrada(uint256 id, address reportadaPor, string descripcion);
    event IncidenciaResuelta(uint256 id, bool descontada, uint256 montoDescuento);
    event DepositoLiberado(address destinatario, uint256 monto);
    event ContratoRescindido(address iniciador, uint256 multa, uint256 timestamp);
    event DisputaAbierta(uint256 montoEnDisputa);
    event DisputaResuelta(address ganador, uint256 monto);

    // ─── Modificadores ───────────────────────────────────────────

    modifier soloPropietario() {
        require(msg.sender == propietario, "Solo el propietario");
        _;
    }

    modifier soloInquilino() {
        require(msg.sender == inquilino, "Solo el inquilino");
        _;
    }

    modifier soloPartes() {
        require(
            msg.sender == propietario || msg.sender == inquilino,
            "Solo las partes del contrato"
        );
        _;
    }

    modifier soloEscribano() {
        require(msg.sender == escribano, "Solo el escribano / arbitro");
        _;
    }

    modifier soloActivo() {
        require(estado == Estado.ACTIVO, "Contrato no activo");
        _;
    }

    // ─────────────────────────────────────────────────────────────
    //  Constructor
    // ─────────────────────────────────────────────────────────────

    /**
     * @param _propietario      Wallet del propietario
     * @param _inquilino        Wallet del inquilino
     * @param _escribano        Wallet del escribano (árbitro)
     * @param _token            Dirección del token ERC-20 de pago
     * @param _oracle           Dirección del oráculo ICL (Chainlink)
     * @param _alquilerMensual  Monto base en unidades del token
     * @param _duracionMeses    Duración del contrato en meses
     * @param _tasaMoraBP       Tasa de mora diaria en basis points
     * @param _mesesMulta       Meses de alquiler como multa por rescisión
     */
    constructor(
        address _propietario,
        address _inquilino,
        address _escribano,
        address _token,
        address _oracle,
        uint256 _alquilerMensual,
        uint256 _duracionMeses,
        uint256 _tasaMoraBP,
        uint256 _mesesMulta
    ) {
        propietario         = _propietario;
        inquilino           = _inquilino;
        escribano           = _escribano;
        arbiter             = _escribano;
        tokenPago           = IERC20(_token);
        oracleICL           = IICLOracle(_oracle);
        alquilerMensual     = _alquilerMensual;
        deposito            = _alquilerMensual * 2;
        tasaMoraDiaria      = _tasaMoraBP;       // ej. 335 = 3.35%
        mesesMultaRescision = _mesesMulta;        // ej. 2
        estado              = Estado.PENDIENTE_FIRMAS;

        // Captura el índice ICL base desde el oráculo al desplegar
        (, int256 iclActual, , ,) = oracleICL.latestRoundData();
        iclBaseIndex = iclActual;

        // Fechas (el contrato se activa al completar firmas)
        fechaInicio = block.timestamp;
        fechaFin    = block.timestamp + (_duracionMeses * 30 days);
        proximoAjuste = block.timestamp + 90 days;
    }

    // ─────────────────────────────────────────────────────────────
    //  1. FIRMAS Y ACTIVACIÓN
    // ─────────────────────────────────────────────────────────────

    /**
     * @notice El propietario firma el contrato.
     */
    function firmarPropietario() external soloPropietario {
        require(estado == Estado.PENDIENTE_FIRMAS, "Ya activado");
        firmadoPropietario = true;
        _intentarActivar();
    }

    /**
     * @notice El inquilino firma y transfiere el depósito al escrow.
     *         Debe haber aprobado al contrato para gastar `deposito` tokens.
     */
    function firmarInquilino() external soloInquilino {
        require(estado == Estado.PENDIENTE_FIRMAS, "Ya activado");
        require(
            tokenPago.transferFrom(inquilino, address(this), deposito),
            "Fallo transferencia deposito"
        );
        depositoBloqueado   = deposito;
        firmadoInquilino    = true;
        _intentarActivar();
    }

    /**
     * @notice El escribano otorga el aval notarial.
     */
    function otorgarAvalNotarial() external soloEscribano {
        require(estado == Estado.PENDIENTE_FIRMAS, "Ya activado");
        avalNotarial = true;
        _intentarActivar();
    }

    /**
     * @dev Activa el contrato si se cumplen las 3 condiciones.
     */
    function _intentarActivar() internal {
        if (firmadoPropietario && firmadoInquilino && avalNotarial) {
            estado     = Estado.ACTIVO;
            ultimoPago = block.timestamp;
            emit ContratoActivado(fechaInicio, fechaFin);
        }
    }

    // ─────────────────────────────────────────────────────────────
    //  2. PAGOS MENSUALES CON MORA AUTOMÁTICA
    // ─────────────────────────────────────────────────────────────

    /**
     * @notice El inquilino abona el alquiler del período vigente.
     *         Si hay mora, el contrato calcula y exige el recargo automáticamente.
     */
    function pagarAlquiler() external soloInquilino soloActivo {
        uint256 diasMora = _calcularDiasMora();
        uint256 interes  = 0;

        if (diasMora > 0) {
            // interés = monto * (tasaMoraBP / 10000) * diasMora
            interes = (alquilerMensual * tasaMoraDiaria * diasMora) / 10000;
            emit MoraAplicada(periodoActual, interes, diasMora);
        }

        uint256 totalAPagar = alquilerMensual + interes;

        require(
            tokenPago.transferFrom(inquilino, propietario, totalAPagar),
            "Fallo pago alquiler"
        );

        periodos[periodoActual] = PeriodoPago({
            mes:           block.timestamp,
            montoBase:     alquilerMensual,
            montoAbonado:  totalAPagar,
            fechaPago:     block.timestamp,
            ajustadoICL:   false
        });

        ultimoPago = block.timestamp;
        estadoPago = EstadoPago.AL_DIA;

        emit PagoRecibido(periodoActual, totalAPagar, block.timestamp);
        periodoActual++;
    }

    /**
     * @dev Calcula los días de mora desde el vencimiento esperado.
     */
    function _calcularDiasMora() internal view returns (uint256) {
        uint256 vencimiento = ultimoPago + 30 days;
        if (block.timestamp <= vencimiento) return 0;
        return (block.timestamp - vencimiento) / 1 days;
    }

    /**
     * @notice Consulta cuánto debe pagar el inquilino hoy (con mora si aplica).
     */
    function montoAPagar() external view returns (uint256 base, uint256 interes, uint256 total) {
        uint256 diasMora = _calcularDiasMora();
        base    = alquilerMensual;
        interes = diasMora > 0
            ? (alquilerMensual * tasaMoraDiaria * diasMora) / 10000
            : 0;
        total   = base + interes;
    }

    // ─────────────────────────────────────────────────────────────
    //  3. ACTUALIZACIÓN INDEXADA POR ORÁCULO ICL
    // ─────────────────────────────────────────────────────────────

    /**
     * @notice Cualquiera puede llamar esta función cada trimestre.
     *         Consulta el oráculo y ajusta el alquiler según la variación del ICL.
     */
    function ajustarPorICL() external soloActivo {
        require(block.timestamp >= proximoAjuste, "Ajuste no disponible aun");

        (, int256 iclActual, , uint256 updatedAt,) = oracleICL.latestRoundData();

        // Oráculo no debe tener más de 2 días sin actualizar
        require(block.timestamp - updatedAt <= 2 days, "Oraculo desactualizado");
        require(iclActual > iclBaseIndex, "ICL no subio");

        uint256 montoAnterior = alquilerMensual;

        // Nuevo alquiler = base × (iclActual / iclBase)
        alquilerMensual = uint256(
            (int256(alquilerMensual) * iclActual) / iclBaseIndex
        );

        iclBaseIndex  = iclActual;
        proximoAjuste = block.timestamp + 90 days;

        emit AlquilerAjustado(montoAnterior, alquilerMensual, iclActual);
    }

    // ─────────────────────────────────────────────────────────────
    //  4. REGISTRO DE INCIDENCIAS ON-CHAIN
    // ─────────────────────────────────────────────────────────────

    /**
     * @notice El inquilino registra un reclamo. Queda sellado con timestamp.
     * @param _descripcion  Texto libre o hash IPFS del reclamo con fotos.
     */
    function registrarIncidencia(string calldata _descripcion)
        external
        soloInquilino
        soloActivo
    {
        uint256 id = contadorIncidencias++;
        incidencias[id] = Incidencia({
            id:                    id,
            reportadaPor:          msg.sender,
            descripcion:           _descripcion,
            timestamp:             block.timestamp,
            resuelta:              false,
            descontadaDeAlquiler:  false
        });
        emit IncidenciaRegistrada(id, msg.sender, _descripcion);
    }

    /**
     * @notice El propietario marca una incidencia como resuelta.
     */
    function resolverIncidencia(uint256 _id) external soloPropietario soloActivo {
        Incidencia storage inc = incidencias[_id];
        require(!inc.resuelta, "Ya resuelta");
        inc.resuelta = true;
        emit IncidenciaResuelta(_id, false, 0);
    }

    /**
     * @notice Si el propietario no responde en el plazo, el escribano
     *         puede autorizar al inquilino a descontar el arreglo del alquiler.
     * @param _id             ID de la incidencia
     * @param _montoDescuento Monto a descontar del próximo alquiler
     */
    function autorizarDescuento(uint256 _id, uint256 _montoDescuento)
        external
        soloEscribano
        soloActivo
    {
        Incidencia storage inc = incidencias[_id];
        require(!inc.resuelta, "Incidencia ya resuelta");
        require(
            block.timestamp >= inc.timestamp + plazoRespuestaPropietario,
            "Plazo de respuesta no vencido"
        );
        require(_montoDescuento <= alquilerMensual, "Descuento excede alquiler");

        inc.resuelta              = true;
        inc.descontadaDeAlquiler  = true;

        // Aplica el descuento al próximo alquiler
        alquilerMensual -= _montoDescuento;

        emit IncidenciaResuelta(_id, true, _montoDescuento);
    }

    // ─────────────────────────────────────────────────────────────
    //  5. RESCISIÓN ANTICIPADA
    // ─────────────────────────────────────────────────────────────

    /**
     * @notice Cualquiera de las partes puede rescindir el contrato.
     *         El que rescinde paga la multa equivalente a N meses de alquiler.
     *         Debe haber aprobado suficientes tokens antes de llamar.
     */
    function rescindirContrato() external soloPartes soloActivo {
        uint256 multa = alquilerMensual * mesesMultaRescision;

        // El iniciador paga la multa a la contraparte
        address contraparte = (msg.sender == inquilino) ? propietario : inquilino;
        require(
            tokenPago.transferFrom(msg.sender, contraparte, multa),
            "Fallo pago multa rescision"
        );

        // Devuelve el depósito al inquilino si no hay disputas abiertas
        _liberarDeposito(inquilino);

        estado = Estado.RESCINDIDO;
        emit ContratoRescindido(msg.sender, multa, block.timestamp);
    }

    // ─────────────────────────────────────────────────────────────
    //  ESCROW — DEPÓSITO DE GARANTÍA
    // ─────────────────────────────────────────────────────────────

    /**
     * @notice Al vencer el contrato, si no hay incidencias sin resolver,
     *         el depósito se devuelve automáticamente al inquilino.
     */
    function cerrarContrato() external soloActivo {
        require(block.timestamp >= fechaFin, "Contrato vigente");

        // Verifica que no haya incidencias abiertas
        bool hayPendientes = false;
        for (uint256 i = 0; i < contadorIncidencias; i++) {
            if (!incidencias[i].resuelta) {
                hayPendientes = true;
                break;
            }
        }

        if (hayPendientes) {
            estado = Estado.EN_DISPUTA;
            emit DisputaAbierta(depositoBloqueado);
        } else {
            _liberarDeposito(inquilino);
            estado = Estado.FINALIZADO;
        }
    }

    /**
     * @notice El árbitro resuelve una disputa sobre el depósito.
     * @param _ganador      Dirección que recibe los fondos del escrow
     * @param _montoGanador Monto para el ganador (resto va al otro)
     */
    function resolverDisputa(address _ganador, uint256 _montoGanador)
        external
        soloEscribano
    {
        require(estado == Estado.EN_DISPUTA, "No hay disputa activa");
        require(
            _ganador == propietario || _ganador == inquilino,
            "Ganador invalido"
        );
        require(_montoGanador <= depositoBloqueado, "Monto excede deposito");

        address perdedor = (_ganador == inquilino) ? propietario : inquilino;
        uint256 restante = depositoBloqueado - _montoGanador;

        if (_montoGanador > 0) {
            tokenPago.transfer(_ganador, _montoGanador);
        }
        if (restante > 0) {
            tokenPago.transfer(perdedor, restante);
        }

        depositoBloqueado = 0;
        estado            = Estado.FINALIZADO;

        emit DisputaResuelta(_ganador, _montoGanador);
    }

    /**
     * @dev Transfiere el depósito bloqueado a la dirección indicada.
     */
    function _liberarDeposito(address _destinatario) internal {
        uint256 monto = depositoBloqueado;
        if (monto == 0) return;
        depositoBloqueado = 0;
        tokenPago.transfer(_destinatario, monto);
        emit DepositoLiberado(_destinatario, monto);
    }

    // ─────────────────────────────────────────────────────────────
    //  CONSULTAS (VIEW)
    // ─────────────────────────────────────────────────────────────

    /// @notice Devuelve el estado general del contrato.
    function estadoGeneral() external view returns (
        Estado   _estado,
        uint256  _alquilerActual,
        uint256  _depositoBloqueado,
        uint256  _diasMora,
        uint256  _proximoAjusteICL,
        uint256  _incidenciasAbiertas
    ) {
        uint256 abiertas = 0;
        for (uint256 i = 0; i < contadorIncidencias; i++) {
            if (!incidencias[i].resuelta) abiertas++;
        }
        return (
            estado,
            alquilerMensual,
            depositoBloqueado,
            _calcularDiasMora(),
            proximoAjuste,
            abiertas
        );
    }

    /// @notice Devuelve los datos de una incidencia por ID.
    function verIncidencia(uint256 _id) external view returns (Incidencia memory) {
        return incidencias[_id];
    }
}
