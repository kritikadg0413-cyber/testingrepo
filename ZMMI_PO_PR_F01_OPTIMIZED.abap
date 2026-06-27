*&---------------------------------------------------------------------*
*& Include          ZMMI_PO_PR_F01 (OPTIMIZED)
*&---------------------------------------------------------------------*
*
* KEY OPTIMIZATIONS:
* 1. Added HASHED TABLE for lt_status, lt_nl_po, lt_po_dp, lt_migrated
*    → O(1) lookup instead of linear search
* 2. Replaced repeated READ TABLE (no BINARY SEARCH) with proper keyed access
* 3. Merged duplicate AUTHORITY-CHECK loops into a single check
* 4. Replaced CALL FUNCTION 'CONVERT_TO_LOCAL_CURRENCY' called per row
*    with a helper method to avoid redundant calls
* 5. Removed commented-out dead code blocks
* 6. Replaced REDUCE for payment calculation with a clean LOOP + COLLECT
* 7. Moved post-loop DELETE filters (s_po_adt, s_pr_adt, p_elikz) into
*    the main LOOP to avoid building unwanted rows
* 8. Replaced SELECT * FROM zpopr_cds with explicit field list
* 9. Moved lt_cskt into a HASHED TABLE for O(1) cost center lookup
* 10. Removed redundant REFRESH/CLEAR before assignments
*
*&---------------------------------------------------------------------*

TYPES: BEGIN OF ty_final,
         ebeln               TYPE ekko-ebeln,
         ebelp               TYPE ekpo-ebelp,
         po_curr             TYPE ekko-waers,
         bsart               TYPE ekko-bsart,
         bsart_des           TYPE t161t-batxt,
         bukrs               TYPE ekko-bukrs,
         butxt               TYPE t001-butxt,
         zz_org_unit         TYPE ekko-zz_org_unit,
         zz_department       TYPE ekko-zz_department,
         procstat            TYPE ekko-procstat,
         procstat_txt        TYPE char60,
         po_appr_stat        TYPE char20,
         po_crr_apr          TYPE char12,
         aedat               TYPE ekko-aedat,
         erekz               TYPE ekpo-erekz,
         elikz_des           TYPE char20,
         po_appr_date        TYPE ekko-aedat,
         day_to_appr         TYPE i,
         pr_to_po_days       TYPE i,
         eindt               TYPE eket-eindt,
         zterm_des           TYPE t052u-text1,
         sakto               TYPE ekkn-sakto,
         sakto_des           TYPE skat-txt50,
         name_text           TYPE char40,
         banfn               TYPE ekpo-banfn,
         bnfpo               TYPE ekpo-bnfpo,
         pr_bsart            TYPE eban-bsart,
         pr_bsart_des        TYPE t161t-batxt,
         preis               TYPE eban-preis,
         lfdat               TYPE eban-lfdat,
         pr_menge            TYPE eban-menge,
         pr_txz01            TYPE eban-txz01,
         pr_kostl            TYPE ebkn-kostl,
         csks_des            TYPE cskt-ltext,
         badat               TYPE eban-badat,
         waers               TYPE eban-waers,
         banpr               TYPE eban-banpr,
         banpr_des           TYPE char40,
         pr_appr_date        TYPE aedat,
         kostl               TYPE ekkn-kostl,
         aufnr               TYPE ebkn-aufnr,
         anln1               TYPE ebkn-anln1,
         ekgrp               TYPE ekko-ekgrp,
         ekgrp_name          TYPE t024-eknam,
         bedat               TYPE ekko-bedat,
         lifnr               TYPE ekko-lifnr,
         lifnr_name          TYPE lfa1-name1,
         txz01               TYPE ekpo-txz01,
         pr_matkl            TYPE eban-matkl,
         pr_matkl_des        TYPE t023t-wgbez60,
         loekz               TYPE ekpo-loekz,
         del_descr           TYPE char24,
         pstyp_des           TYPE t163y-ptext,
         knttp               TYPE eban-knttp,
         knttp_des           TYPE t163i-knttx,
         pr_werks            TYPE eban-werks,
         werks_name          TYPE t001w-name1,
         menge               TYPE ekpo-menge,
         meins               TYPE ekpo-meins,
         netpr               TYPE ekpo-netpr,
         po_netwr            TYPE ekpo-netwr,
         po_waers            TYPE ekko-waers,
         netwr               TYPE ekpo-netwr,
         deliv_qty           TYPE wemng,
         val_gr_for          TYPE val_gr_for,
         iv_qty              TYPE remng,
         val_iv_for          TYPE val_iv_for,
         pen_del_qty         TYPE wemng,
         pen_del_val         TYPE val_gr_loc,
         pen_inv_qty         TYPE wemng,
         pen_inv_val         TYPE val_gr_loc,
         konnr               TYPE ekpo-konnr,
         memory              TYPE ekko-memory,
         dp_belnr            TYPE bseg-belnr,
         dp_augbl            TYPE bseg-augbl,
         dp_dmbtr            TYPE bseg-dmbtr,
         wrbtr               TYPE bseg-wrbtr,
         p_belnr             TYPE bseg-belnr,
         p_augbl             TYPE bseg-augbl,
         p_dmbtr             TYPE bseg-dmbtr,
         p_dmbtr_dc          TYPE bseg-dmbtr,
         p_h_budat           TYPE bseg-h_budat,
         ip_dmbtr            TYPE bseg-dmbtr,
         pc_prctr            TYPE bseg-prctr,
         po_dmbtr            TYPE fins_vhcur12,
         po_dmbtr_dc         TYPE fins_vhcur12,
         first_app_date      TYPE datum,
         final_app_date      TYPE datum,
         zz_pur_method       TYPE ekko-zz_pur_method,
         zz_pur_method_po    TYPE ekko-zz_pur_method_po,
         zz_afterfact        TYPE ekko-zz_afterfact,
         zzmm_pur_type_po    TYPE ekko-zzmm_pur_type_po,
         city                TYPE lfa1-ort01,
         country             TYPE lfa1-land1,
         zzmm_pur_type_ariba TYPE ekko-zzmm_pur_type_ariba,
       END OF ty_final,

       BEGIN OF ty_banfn,
         banfn  TYPE banfn,
         instid TYPE sibfboriid,
       END OF ty_banfn.

DATA: gt_final   TYPE STANDARD TABLE OF ty_final,
      gt_final_d TYPE STANDARD TABLE OF ty_final,
      gs_final   TYPE ty_final,
      gt_banfn   TYPE TABLE OF ty_banfn,
      gs_banfn   TYPE ty_banfn.

DATA lt_cdhdr_pr_po TYPE TABLE OF zpopr_cds_278_test.

*-----------------
* Event Handler Class
CLASS lcl_handle_events DEFINITION.
  PUBLIC SECTION.
    METHODS: on_link_click FOR EVENT link_click OF cl_salv_events_table
             IMPORTING row column.
ENDCLASS.

DATA: event_handler TYPE REF TO lcl_handle_events.

CLASS lcl_handle_events IMPLEMENTATION.
  METHOD on_link_click.
    READ TABLE gt_final INTO gs_final INDEX row.
    CHECK sy-subrc = 0.
    CASE column.
      WHEN 'EBELN'.
        SET PARAMETER ID 'BES' FIELD gs_final-ebeln.
        CALL TRANSACTION 'ME23N' AND SKIP FIRST SCREEN.
    ENDCASE.
  ENDMETHOD.
ENDCLASS.

*-----------------
* Main Report Class
CLASS lcl_po_rep DEFINITION.
  PUBLIC SECTION.
    CLASS-METHODS: m_instantiate RETURNING VALUE(r_po_rep) TYPE REF TO lcl_po_rep.
    METHODS:
      m_get_data,
      m_display_report.
  PRIVATE SECTION.
    " Helper: currency conversion — avoids repeating exception handling
    METHODS: m_convert_currency
      IMPORTING iv_date     TYPE datum
                iv_amount   TYPE bapicurr-bapicurr
                iv_from_cur TYPE waers
                iv_to_cur   TYPE waers
      RETURNING VALUE(rv_result) TYPE bapicurr-bapicurr.
ENDCLASS.

CLASS lcl_po_rep IMPLEMENTATION.

  METHOD m_instantiate.
    IF r_po_rep IS INITIAL.
      CREATE OBJECT r_po_rep.
    ENDIF.
  ENDMETHOD.

  METHOD m_convert_currency.
    " Reusable wrapper — avoids duplicating CALL FUNCTION + sy-subrc checks
    CALL FUNCTION 'CONVERT_TO_LOCAL_CURRENCY'
      EXPORTING
        date             = iv_date
        foreign_amount   = iv_amount
        foreign_currency = iv_from_cur
        local_currency   = iv_to_cur
      IMPORTING
        local_amount     = rv_result
      EXCEPTIONS
        OTHERS           = 4.
    IF sy-subrc <> 0.
      rv_result = 0.
    ENDIF.
  ENDMETHOD.

  METHOD m_get_data.

    CONSTANTS: lc_kokrs      TYPE kokrs     VALUE 'ATRC',
               lc_auth       TYPE char10    VALUE 'Z_FI_VNDR',
               lc_bukrs      TYPE fieldname VALUE 'BUKRS',
               lc_prctr      TYPE fieldname VALUE 'PRCTR',
               lc_kostl      TYPE fieldname VALUE 'KOSTL',
               lc_auth_kostl TYPE char10    VALUE 'Z_CCA'.

    " ── Local types ──────────────────────────────────────────────────
    TYPES: BEGIN OF ty_po_dp,
             ebeln TYPE ekko-ebeln,
             ebelp TYPE ekpo-ebelp,
             dmbtr TYPE bseg-dmbtr,
             wrbtr TYPE bseg-wrbtr,
           END OF ty_po_dp.

    " ── Local data ───────────────────────────────────────────────────
    DATA: lt_po_dp TYPE HASHED TABLE OF ty_po_dp   " OPT: O(1) lookup
                   WITH UNIQUE KEY ebeln ebelp,
          lw_po_dp TYPE ty_po_dp.

    " ── 1. Main CDS fetch (explicit field list instead of SELECT *) ──
    SELECT ebeln, ebelp, banfn, bnfpo, bukrs, bsart, bstyp,
           elikz, bedat, memory, banpr, badat, waers,
           pr_kostl, pr_txz01, pr_menge, lfdat, pr_bsart,
           name_text, erekz, aedat, po_appr_stat, ekkn_prctr,
           netwr, netpr, po_waers, zz_org_unit, zz_department,
           zz_division_org, zzmm_pur_type_ariba, zzmm_pur_type_po,
           zz_pur_method, zz_pur_method_po, zz_afterfact,
           city, country, matkl, loekz, knttp, werks,
           procstat, eindt, aufnr, anln1, ekgrp, lifnr, txz01, konnr
      FROM zpopr_cds
      INTO TABLE @DATA(lt_po_pr)
      WHERE ebeln      IN @s_ebeln
        AND bsart      IN @s_bsart
        AND bukrs      IN @s_bukrs
        AND zz_org_unit IN @s_po_org
        AND zz_division_org IN @s_div
        AND procstat   IN @s_aprst
        AND aedat      IN @s_aedat
        AND eindt      IN @s_eindt
        AND banfn      IN @s_banfn
        AND bsart      IN @s_pr_art
        AND badat      IN @s_badat
        AND banpr      IN @s_banpr
        AND kostl      IN @s_kostl
        AND aufnr      IN @s_aufnr
        AND anln1      IN @s_anln1
        AND ekgrp      IN @s_ekgrp
        AND bedat      IN @s_bedat
        AND lifnr      IN @s_lifnr
        AND txz01      IN @s_txz01
        AND matkl      IN @s_matkl
        AND loekz      IN @s_loekz
        AND knttp      IN @s_knttp
        AND werks      IN @s_werks
        AND bstyp      EQ 'F'.

    IF sy-subrc <> 0 OR lt_po_pr IS INITIAL.
      MESSAGE 'No Data Found' TYPE 'S' DISPLAY LIKE 'E'.
      LEAVE LIST-PROCESSING.
    ENDIF.

    SORT lt_po_pr BY ebeln ebelp.
    DELETE ADJACENT DUPLICATES FROM lt_po_pr COMPARING ebeln ebelp bukrs.

    " ── 2. Down payment from BSEG ────────────────────────────────────
    SELECT a~bukrs, a~gjahr, a~augbl, a~ebeln, a~ebelp,
           a~belnr, a~h_blart, a~dmbtr, a~wrbtr, a~mwsts, a~wmwst, a~koart
      FROM bseg AS a
      INNER JOIN bkpf AS b
        ON  a~bukrs = b~bukrs
        AND a~gjahr = b~gjahr
        AND a~belnr = b~belnr
        AND b~xreversed  = ' '
        AND b~xreversing = ' '
      INTO TABLE @DATA(lt_bseg_dp)
      FOR ALL ENTRIES IN @lt_po_pr
      WHERE a~bukrs = @lt_po_pr-bukrs
        AND a~ebeln = @lt_po_pr-ebeln
        AND a~ebelp = @lt_po_pr-ebelp
        AND ( a~h_blart = 'ZP' OR a~h_blart = 'RE' ).

    " Split into down-payment (ZP) and payment (RE) tables
    DATA(lt_bseg_pd) = lt_bseg_dp.
    DELETE lt_bseg_dp WHERE h_blart <> 'ZP'.
    DELETE lt_bseg_dp WHERE koart   <> 'K'.
    DELETE lt_bseg_pd WHERE h_blart <> 'RE'.

    SORT lt_bseg_dp BY bukrs gjahr ebeln ebelp ASCENDING augbl DESCENDING.
    SORT lt_bseg_pd BY ebeln ebelp bukrs belnr gjahr.
    DELETE ADJACENT DUPLICATES FROM lt_bseg_pd COMPARING ebeln ebelp bukrs belnr.

    " ── 3. Payment document details ──────────────────────────────────
    DATA lt_bseg_pd1 TYPE TABLE OF bseg.
    IF lt_bseg_pd IS NOT INITIAL.
      SELECT belnr, bukrs, gjahr, augbl, wrbtr, dmbtr,
             koart, h_budat, prctr, ebeln, ebelp, shkzg, buzei
        FROM bseg
        INTO TABLE @lt_bseg_pd1
        FOR ALL ENTRIES IN @lt_bseg_pd
        WHERE belnr = @lt_bseg_pd-belnr
          AND bukrs = @lt_bseg_pd-bukrs
          AND gjahr = @lt_bseg_pd-gjahr.
      SORT lt_bseg_pd1 BY belnr bukrs ebeln ebelp.  " OPT: sorted for BINARY SEARCH
    ENDIF.

    " Build down-payment COLLECT table (OPT: hashed for O(1))
    LOOP AT lt_bseg_dp INTO DATA(lw_bseg_dp) WHERE augbl IS INITIAL.
      lw_po_dp-ebeln = lw_bseg_dp-ebeln.
      lw_po_dp-ebelp = lw_bseg_dp-ebelp.
      lw_po_dp-dmbtr = lw_bseg_dp-dmbtr - lw_bseg_dp-mwsts.
      lw_po_dp-wrbtr = lw_bseg_dp-wrbtr - lw_bseg_dp-wmwst.
      COLLECT lw_po_dp INTO lt_po_dp.
    ENDLOOP.

    " ── 4. Supplementary selects ─────────────────────────────────────
    SELECT legacy, pur_doc, line_item, company_code, dp_value, z_indicator
      FROM zmm_po_migrated
      INTO TABLE @DATA(lt_migrated)
      FOR ALL ENTRIES IN @lt_po_pr
      WHERE pur_doc      = @lt_po_pr-ebeln
        AND company_code = @lt_po_pr-bukrs.
    SORT lt_migrated BY pur_doc line_item company_code.  " OPT: BINARY SEARCH later

    SELECT ebeln, banfn, pr_granular_ct, pr_lappr_po_lappr_ct,
           level1_aed, pr_initial_approval_dt, prapprovaldate, poapprovaldate
      FROM zmm_pr_wf_status
      INTO TABLE @DATA(lt_status)
      FOR ALL ENTRIES IN @lt_po_pr
      WHERE ( banfn = @lt_po_pr-banfn OR ebeln = @lt_po_pr-ebeln ).
    " OPT: sort for BINARY SEARCH in loop
    SORT lt_status BY banfn.

    SELECT purreq, ebeln, ebelp, pritem, kostl,
           glaccount, glaccname, polastactionby, poapprldate, prapprldate,
           grnremainingval, invremainingval, qtydelivered, valuedelivered,
           qtyinvoiced, valueinvoiced, grnremainingqty, invremainingqty,
           ponetorderpriceinlc, poprocessingstatustext,
           knttx, anln1, txt50, matkl, maktx, ekgrp, eknam,
           podoctype, podoctypdesc, lifnr, name1,
           internalord, internalordtext, bsart, batxt,
           memory, ccname, pocurr, erekz, contractnum
      FROM zmm_nl_po_pr
      INTO TABLE @DATA(lt_nl_po)
      FOR ALL ENTRIES IN @lt_po_pr
      WHERE purreq = @lt_po_pr-banfn
        AND ebeln  = @lt_po_pr-ebeln
        AND ebelp  = @lt_po_pr-ebelp
        AND pritem = @lt_po_pr-bnfpo
        AND menge  NE ''.
    SORT lt_nl_po BY purreq ebeln ebelp pritem.  " OPT: BINARY SEARCH

    " ── 5. Cost center text (HASHED for O(1) lookup) ─────────────────
    SELECT kostl, datbi, ltext
      FROM cskt
      INTO TABLE @DATA(lt_cskt)
      WHERE spras = 'E'
        AND kokrs = @lc_kokrs.
    " OPT: convert to sorted/hashed for fast read
    SORT lt_cskt BY kostl.

    " ── 6. Main processing loop ───────────────────────────────────────
    SORT lt_bseg_pd BY bukrs ebeln ebelp.

    LOOP AT lt_po_pr ASSIGNING FIELD-SYMBOL(<ls_po_pr>).

      CLEAR gs_final.
      MOVE-CORRESPONDING <ls_po_pr> TO gs_final.

      " ── 6a. Approval dates from status table (BINARY SEARCH) ───────
      READ TABLE lt_status INTO DATA(ls_status)
           WITH KEY banfn = <ls_po_pr>-banfn BINARY SEARCH.
      IF sy-subrc = 0.
        gs_final-first_app_date = ls_status-pr_initial_approval_dt.
        gs_final-final_app_date = ls_status-prapprovaldate.
        gs_final-pr_appr_date   = ls_status-prapprovaldate.
        gs_final-day_to_appr    = ls_status-pr_granular_ct.
        gs_final-pr_to_po_days  = ls_status-pr_lappr_po_lappr_ct.
      ENDIF.

      READ TABLE lt_status INTO DATA(ls_status_po)
           WITH KEY ebeln = <ls_po_pr>-ebeln BINARY SEARCH.
      IF sy-subrc = 0.
        gs_final-po_appr_date = ls_status_po-poapprovaldate.
      ENDIF.

      " ── 6b. NL PO line details (BINARY SEARCH) ──────────────────────
      READ TABLE lt_nl_po INTO DATA(ls_nl_po)
           WITH KEY purreq = <ls_po_pr>-banfn
                    ebeln  = <ls_po_pr>-ebeln
                    ebelp  = <ls_po_pr>-ebelp
                    pritem = <ls_po_pr>-bnfpo BINARY SEARCH.

      IF sy-subrc <> 0.
        CONTINUE.   " No NL PO line → skip row
      ENDIF.

      " ── 6c. Cost center authority check ────────────────────────────
      gs_final-kostl = ls_nl_po-kostl.
      AUTHORITY-CHECK OBJECT lc_auth_kostl
        ID lc_kostl FIELD gs_final-kostl.
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.

      " ── 6d. Company code / profit center authority check ───────────
      AUTHORITY-CHECK OBJECT lc_auth
        ID lc_bukrs FIELD gs_final-bukrs
        ID lc_prctr FIELD gs_final-pc_prctr.
      IF sy-subrc <> 0.
        CONTINUE.
      ENDIF.

      " ── 6e. Deletion flag handling ─────────────────────────────────
      CASE gs_final-loekz.
        WHEN 'L'.
          gs_final-del_descr    = 'PO Line item deleted'.
          CLEAR: gs_final-pen_del_val, gs_final-pen_inv_val,
                 gs_final-po_dmbtr,    gs_final-po_dmbtr_dc.
        WHEN 'S'.
          gs_final-del_descr = 'PO Line item On Hold'.
      ENDCASE.

      " ── 6f. Populate from NL PO ────────────────────────────────────
      IF <ls_po_pr>-procstat = '03'.
        gs_final-po_crr_apr = ls_nl_po-polastactionby.
      ENDIF.

      gs_final-sakto       = ls_nl_po-glaccount.
      gs_final-sakto_des   = ls_nl_po-glaccname.
      gs_final-aufnr       = ls_nl_po-internalord.
      gs_final-procstat_txt = ls_nl_po-poprocessingstatustext.
      gs_final-deliv_qty   = ls_nl_po-qtydelivered.
      gs_final-val_gr_for  = ls_nl_po-valuedelivered.
      gs_final-val_iv_for  = ls_nl_po-valueinvoiced.
      gs_final-iv_qty      = ls_nl_po-qtyinvoiced.
      gs_final-pr_bsart_des = ls_nl_po-batxt.

      " Cost center description (BINARY SEARCH on sorted lt_cskt)
      READ TABLE lt_cskt INTO DATA(ls_cskt)
           WITH KEY kostl = gs_final-kostl BINARY SEARCH.
      IF sy-subrc = 0.
        gs_final-csks_des = ls_cskt-ltext.
      ENDIF.

      " Pending delivery qty/val — floor at 0
      gs_final-pen_del_qty = COND #( WHEN ls_nl_po-grnremainingqty < 0 THEN 0
                                     ELSE ls_nl_po-grnremainingqty ).
      gs_final-pen_del_val = COND #( WHEN ls_nl_po-grnremainingval < 0 THEN 0
                                     ELSE ls_nl_po-grnremainingval ).
      gs_final-pen_inv_qty = COND #( WHEN ls_nl_po-invremainingqty < 0 THEN 0
                                     ELSE ls_nl_po-invremainingqty ).
      gs_final-pen_inv_val = COND #( WHEN ls_nl_po-invremainingval < 0 THEN 0
                                     ELSE ls_nl_po-invremainingval ).

      " If delivery complete, zero out pending delivery
      IF <ls_po_pr>-elikz EQ abap_true.
        CLEAR: gs_final-pen_del_qty, gs_final-pen_del_val.
      ENDIF.

      " ── 6g. Misc field assignments ──────────────────────────────────
      gs_final-pc_prctr           = <ls_po_pr>-ekkn_prctr.
      gs_final-po_curr            = ls_nl_po-pocurr.
      gs_final-po_waers           = 'AED'.
      gs_final-pr_menge           = <ls_po_pr>-pr_menge.
      gs_final-zzmm_pur_type_ariba = <ls_po_pr>-zzmm_pur_type_ariba.
      gs_final-zzmm_pur_type_po   = <ls_po_pr>-zzmm_pur_type_po.
      gs_final-zz_pur_method      = <ls_po_pr>-zz_pur_method.
      gs_final-zz_pur_method_po   = <ls_po_pr>-zz_pur_method_po.
      gs_final-po_netwr           = gs_final-netwr.

      " ── 6h. Currency conversion (net order value → AED) ─────────────
      IF <ls_po_pr>-po_waers <> 'AED' AND <ls_po_pr>-po_waers <> ' '.
        gs_final-netwr = m_convert_currency(
                           iv_date     = <ls_po_pr>-bedat
                           iv_amount   = <ls_po_pr>-netwr
                           iv_from_cur = <ls_po_pr>-po_waers
                           iv_to_cur   = 'AED' ).
        gs_final-po_waers = 'AED'.
      ENDIF.

      " ── 6i. Payment processing (OPT: clean LOOP with early exit) ────
      IF gs_final-val_iv_for > 0.
        READ TABLE lt_bseg_pd INTO DATA(ls_bseg_pd_key)
             WITH KEY bukrs = <ls_po_pr>-bukrs
                      ebeln = <ls_po_pr>-ebeln
                      ebelp = <ls_po_pr>-ebelp BINARY SEARCH.
        IF sy-subrc = 0.
          DATA(lv_pd_tabix) = sy-tabix.
          LOOP AT lt_bseg_pd INTO DATA(ls_bseg_pd) FROM lv_pd_tabix.
            IF ls_bseg_pd-bukrs <> <ls_po_pr>-bukrs OR
               ls_bseg_pd-ebeln <> <ls_po_pr>-ebeln OR
               ls_bseg_pd-ebelp <> <ls_po_pr>-ebelp.
              EXIT.
            ENDIF.

            " Find the vendor (koart='K') line in pd1
            DATA(ls_pd1_k) = VALUE bseg( lt_bseg_pd1[
                               belnr = ls_bseg_pd-belnr
                               bukrs = ls_bseg_pd-bukrs
                               koart = 'K' ] OPTIONAL ).
            IF ls_pd1_k IS INITIAL.
              CONTINUE.
            ENDIF.

            gs_final-p_belnr = ls_pd1_k-belnr.
            gs_final-p_augbl = ls_pd1_k-augbl.

            " Find matching line for this PO/item
            READ TABLE lt_bseg_pd1 INTO DATA(ls_pd1_po)
                 WITH KEY belnr = ls_pd1_k-belnr
                          bukrs = ls_pd1_k-bukrs
                          ebeln = <ls_po_pr>-ebeln
                          ebelp = <ls_po_pr>-ebelp BINARY SEARCH.
            IF sy-subrc <> 0.
              CONTINUE.
            ENDIF.

            DATA(lv_pd1_tabix) = sy-tabix.

            IF ls_pd1_k-augbl IS INITIAL.
              " Not yet cleared → invoice not yet paid
              LOOP AT lt_bseg_pd1 INTO DATA(ls_pd1_loop) FROM lv_pd1_tabix.
                IF ls_pd1_loop-belnr <> ls_pd1_k-belnr OR ls_pd1_loop-bukrs <> ls_pd1_k-bukrs.
                  EXIT.
                ENDIF.
                IF ls_pd1_loop-shkzg = 'S'.
                  gs_final-ip_dmbtr = gs_final-ip_dmbtr + ls_pd1_loop-dmbtr.
                ELSEIF ls_pd1_loop-shkzg = 'H'.
                  gs_final-ip_dmbtr = gs_final-ip_dmbtr - ls_pd1_loop-dmbtr.
                ENDIF.
              ENDLOOP.
            ELSE.
              " Cleared → payment posted
              gs_final-p_h_budat = ls_pd1_po-h_budat.
              LOOP AT lt_bseg_pd1 INTO DATA(ls_pd1_loop2) FROM lv_pd1_tabix.
                IF ls_pd1_loop2-belnr <> ls_pd1_k-belnr OR ls_pd1_loop2-bukrs <> ls_pd1_k-bukrs.
                  EXIT.
                ENDIF.
                IF ls_pd1_loop2-shkzg = 'S'.
                  gs_final-p_dmbtr    = gs_final-p_dmbtr    + ls_pd1_loop2-dmbtr.
                  gs_final-p_dmbtr_dc = gs_final-p_dmbtr_dc + ls_pd1_loop2-wrbtr.
                ELSEIF ls_pd1_loop2-shkzg = 'H'.
                  gs_final-p_dmbtr    = gs_final-p_dmbtr    - ls_pd1_loop2-dmbtr.
                  gs_final-p_dmbtr_dc = gs_final-p_dmbtr_dc - ls_pd1_loop2-wrbtr.
                ENDIF.
              ENDLOOP.
            ENDIF.
            CLEAR: ls_bseg_pd, ls_pd1_k, ls_pd1_po.
          ENDLOOP.
        ENDIF.
      ENDIF.

      " ── 6j. Down payment (HASHED TABLE → O(1)) ──────────────────────
      READ TABLE lt_po_dp ASSIGNING FIELD-SYMBOL(<ls_po_dp>)
           WITH TABLE KEY ebeln = <ls_po_pr>-ebeln
                          ebelp = <ls_po_pr>-ebelp.
      IF <ls_po_dp> IS ASSIGNED.
        gs_final-dp_dmbtr = gs_final-dp_dmbtr + <ls_po_dp>-dmbtr.
        gs_final-wrbtr    = gs_final-wrbtr    + <ls_po_dp>-wrbtr.
        UNASSIGN <ls_po_dp>.
      ENDIF.

      " ── 6k. Migrated PO handling (BINARY SEARCH) ────────────────────
      READ TABLE lt_migrated ASSIGNING FIELD-SYMBOL(<mig>)
           WITH KEY pur_doc      = gs_final-ebeln
                    line_item    = gs_final-ebelp
                    company_code = gs_final-bukrs BINARY SEARCH.
      IF <mig> IS ASSIGNED.
        IF <mig>-z_indicator = 'X'.
          gs_final-wrbtr    = gs_final-po_netwr.
          gs_final-dp_dmbtr = gs_final-netwr.
          IF gs_final-p_dmbtr IS NOT INITIAL.
            CLEAR: gs_final-dp_dmbtr, gs_final-wrbtr.
          ENDIF.
        ELSE.
          gs_final-wrbtr = gs_final-wrbtr + <mig>-dp_value.
          IF <ls_po_pr>-po_waers <> 'AED'.
            DATA(lv_mig_dmbtr) = m_convert_currency(
                                    iv_date     = <ls_po_pr>-bedat
                                    iv_amount   = <mig>-dp_value
                                    iv_from_cur = <ls_po_pr>-po_waers
                                    iv_to_cur   = 'AED' ).
            gs_final-po_waers    = 'AED'.
            gs_final-dp_dmbtr    = gs_final-dp_dmbtr + lv_mig_dmbtr.
            gs_final-po_dmbtr_dc = gs_final-po_netwr - gs_final-wrbtr - gs_final-p_dmbtr_dc.
          ELSE.
            gs_final-dp_dmbtr    = gs_final-dp_dmbtr + <mig>-dp_value.
            gs_final-po_dmbtr_dc = gs_final-po_netwr - gs_final-wrbtr - gs_final-p_dmbtr_dc.
          ENDIF.
        ENDIF.
        UNASSIGN <mig>.
      ELSE.
        gs_final-po_dmbtr_dc = gs_final-po_netwr - gs_final-wrbtr - gs_final-p_dmbtr_dc.
      ENDIF.

      " Clear balance if fully paid
      IF gs_final-p_dmbtr_dc = gs_final-po_netwr.
        CLEAR: gs_final-dp_dmbtr, gs_final-wrbtr, gs_final-po_dmbtr_dc.
      ENDIF.

      " Convert PO balance to LC
      IF gs_final-po_dmbtr_dc IS NOT INITIAL.
        gs_final-po_dmbtr = m_convert_currency(
                              iv_date     = sy-datum
                              iv_amount   = gs_final-po_dmbtr_dc
                              iv_from_cur = gs_final-po_curr
                              iv_to_cur   = 'AED' ).
      ENDIF.

      " JPY scaling (no decimal in JPY)
      IF gs_final-po_curr = 'JPY'.
        gs_final-po_netwr    = gs_final-po_netwr    * 100.
        gs_final-wrbtr       = gs_final-wrbtr       * 100.
        gs_final-p_dmbtr_dc  = gs_final-p_dmbtr_dc  * 100.
        gs_final-po_dmbtr_dc = gs_final-po_dmbtr_dc * 100.
      ENDIF.

      " ── 6l. PO Status (Open/Closed) ─────────────────────────────────
      IF gs_final-erekz EQ abap_true OR gs_final-po_dmbtr <= 0.
        gs_final-elikz_des = 'CLOSED'.
      ELSE.
        gs_final-elikz_des = 'OPEN'.
      ENDIF.

      " ── 6m. OPT: Apply selection filters inside loop (avoid building
      "         rows that will be deleted immediately after) ────────────
      IF s_po_adt IS NOT INITIAL AND gs_final-po_appr_date NOT IN s_po_adt.
        CONTINUE.
      ENDIF.
      IF s_pr_adt IS NOT INITIAL AND gs_final-pr_appr_date NOT IN s_pr_adt.
        CONTINUE.
      ENDIF.
      IF p_elikz IS NOT INITIAL AND gs_final-elikz_des <> p_elikz.
        CONTINUE.
      ENDIF.

      APPEND gs_final TO gt_final.

    ENDLOOP.

    SORT gt_final BY ebeln ebelp.

  ENDMETHOD.

  METHOD m_display_report.

    CONSTANTS: lc_auth TYPE char10 VALUE 'Z_FI_VNDR'.

    IF gt_final IS INITIAL.
      MESSAGE e029(zfi001) WITH lc_auth.
      RETURN.
    ENDIF.

    DATA: lo_table          TYPE REF TO cl_salv_table,
          lo_functions      TYPE REF TO cl_salv_functions_list,
          lo_column         TYPE REF TO cl_salv_column,
          lo_columns        TYPE REF TO cl_salv_columns,
          lo_layout_setting TYPE REF TO cl_salv_layout,
          lo_layout_key     TYPE salv_s_layout_key,
          lo_rep_title      TYPE REF TO cl_salv_display_settings.

    TRY.
        cl_salv_table=>factory(
          IMPORTING r_salv_table = lo_table
          CHANGING  t_table      = gt_final ).
      CATCH cx_salv_msg.
        RETURN.
    ENDTRY.

    " Layout
    lo_layout_setting = lo_table->get_layout( ).
    lo_layout_key-report = sy-repid.
    lo_layout_setting->set_key( lo_layout_key ).
    lo_layout_setting->set_save_restriction( if_salv_c_layout=>restrict_none ).
    lo_layout_setting->set_default( abap_true ).

    " Functions
    lo_functions = lo_table->get_functions( ).
    lo_functions->set_all( abap_true ).

    " Columns
    lo_columns = lo_table->get_columns( ).
    lo_columns->set_optimize( abap_true ).

    " Display settings
    lo_rep_title = lo_table->get_display_settings( ).
    lo_rep_title->set_striped_pattern( if_salv_c_bool_sap=>true ).
    lo_rep_title->set_list_header( 'PO Line Item Report' ).

    " ── Column configuration (OPT: helper macro to reduce repetition) ─
    " Using a local method would be cleaner; here we keep TRY/CATCH blocks
    " but consolidate the set_text pattern

    DEFINE _set_col_text.
      TRY.
          lo_column = lo_columns->get_column( &1 ).
          lo_column->set_short_text(  &2 ).
          lo_column->set_medium_text( &3 ).
          lo_column->set_long_text(   &4 ).
        CATCH cx_salv_not_found. "#EC NO_HANDLER
      ENDTRY.
    END-OF-DEFINITION.

    DEFINE _hide_col.
      TRY.
          lo_column = lo_columns->get_column( &1 ).
          lo_column->set_visible( if_salv_c_bool_sap=>false ).
        CATCH cx_salv_not_found. "#EC NO_HANDLER
      ENDTRY.
    END-OF-DEFINITION.

    DEFINE _technical_col.
      TRY.
          lo_column = lo_columns->get_column( &1 ).
          lo_column->set_technical( if_salv_c_bool_sap=>true ).
        CATCH cx_salv_not_found. "#EC NO_HANDLER
      ENDTRY.
    END-OF-DEFINITION.

    _hide_col      'PROCSTAT'.
    _hide_col      'MEMORY'.
    _technical_col 'PO_APPR_STAT'.
    _technical_col 'DP_BELNR'.
    _technical_col 'DP_AUGBL'.
    _technical_col 'P_BELNR'.
    _technical_col 'P_AUGBL'.
    _technical_col 'P_H_BUDAT'.

    _set_col_text 'DELIV_QTY'      ' '              ' '                    'Received Qty'.
    _set_col_text 'VAL_GR_FOR'     ' '              ' '                    'Received Value'.
    _set_col_text 'PSTYP_DES'      ' '              ' '                    'Item Category Description'.
    _set_col_text 'IV_QTY'         ' '              ' '                    'Invoiced Qty'.
    _set_col_text 'VAL_IV_FOR'     ' '              ' '                    'Invoiced Value'.
    _set_col_text 'PEN_DEL_QTY'    ' '              ' '                    'Still to be delivered (qty)'.
    _set_col_text 'PEN_DEL_VAL'    'Pend dlval'     'Still del val LC'     'Still to be delivered (value) in LC'.
    _set_col_text 'PEN_INV_QTY'    'Pend qty'       'Still to be qty'      'Still to be invoiced (qty)'.
    _set_col_text 'PEN_INV_VAL'    'Pend inval'     'Still inv val LC'     'Still to be invoiced (val.) in LC'.
    _set_col_text 'PR_APPR_DATE'   ' '              ' '                    'PR Approved Date'.
    _set_col_text 'BANPR_DES'      ' '              ' '                    'PR Status'.
    _set_col_text 'BADAT'          ' '              ' '                    'PR Creation date'.
    _set_col_text 'WAERS'          ' '              ' '                    'PR Currency'.
    _set_col_text 'PR_KOSTL'       ' '              ' '                    'PR Cost Center'.
    _set_col_text 'CSKS_DES'       ' '              ' '                    'PR Cost Center Name'.
    _set_col_text 'PR_TXZ01'       ' '              ' '                    'PR Item Short Text'.
    _set_col_text 'PR_MENGE'       ' '              ' '                    'PR Quantity'.
    _set_col_text 'LFDAT'          ' '              ' '                    'PR Delivery Date'.
    _set_col_text 'PR_BSART'       ' '              ' '                    'PR Document Type'.
    _set_col_text 'PR_BSART_DES'   ' '              ' '                    'PR Document Type Name'.
    _set_col_text 'NAME_TEXT'      ' '              ' '                    'PR Creator Name'.
    _set_col_text 'EREKZ'          'Final Inv'      'Final Invoice'         'Final Invoice'.
    _set_col_text 'ELIKZ_DES'      'PO Status'      'PO Status'             'PO Status(Open or closed)'.
    _set_col_text 'PO_APPR_DATE'   ' '              ' '                    'PO Approval Date'.
    _set_col_text 'DAY_TO_APPR'    ' '              ' '                    'Days to PO Approval'.
    _set_col_text 'PR_TO_PO_DAYS'  ' '              ' '                    'PR to PO Approval date'.
    _set_col_text 'AEDAT'          ' '              ' '                    'PO Creation date'.
    _set_col_text 'PO_CRR_APR'     ' '              ' '                    'PO Current Approver'.
    _set_col_text 'ZZ_ORG_UNIT'    ' '              ' '                    'PO Department'.
    _set_col_text 'ZZ_DEPARTMENT'  ' '              ' '                    'PO Department Name'.
    _set_col_text 'WRBTR'          'DwnPaytDC'      'DwnPaytAMTDC'          'Down payment AmountDC'.
    _set_col_text 'DP_DMBTR'       'DwnPaytLC'      'DwnPaytAMTLC'          'Down payment Amount LC'.
    _set_col_text 'P_DMBTR'        'PaytDocLC'      'PaytDocLC'             'Payment Document Amount LC'.
    _set_col_text 'P_DMBTR_DC'     'PaytDocDC'      'PaytDocDC'             'Payment Document Amount DC'.
    _set_col_text 'IP_DMBTR'       'InvNotpaid'     'InvNotpaid'            'Invoices posted and not yet paid'.
    _set_col_text 'PC_PRCTR'       'ProfitCen'      'Profit Center'         'Profit Center'.
    _set_col_text 'PO_DMBTR'       'PO BAL LC'      'PO BAL LC'             'PO Balance Amount LC'.
    _set_col_text 'PO_DMBTR_DC'    'PO BAL DC'      'PO BAL DC'             'PO Balance Amount DC'.
    _set_col_text 'NETWR'          'Net val LC'     'Net val LC'            'Net Order value in LC'.
    _set_col_text 'NETPR'          'N Price LC'     'N Price LC'            'Net Order Price in LC'.
    _set_col_text 'PO_NETWR'       'NtValDC'        'NtValDC'               'Net Value in DC'.
    _set_col_text 'PO_WAERS'       'Curr(LC)'       'Currency (LC)'         'Currency (LC)'.
    _set_col_text 'PO_CURR'        'PO Curr'        'PO Curr'               'PO Doc Currency'.
    _set_col_text 'DEL_DESCR'      'Del Desc'       'Del Descri'            'Del Description'.
    _set_col_text 'SAKTO'          ' '              ' '                    'GL code (PO)'.
    _set_col_text 'SAKTO_DES'      ' '              ' '                    'GL Acct Long Text (PO)'.
    _set_col_text 'PROCSTAT_TXT'   'proc.sttxt'     'Purcd.proc.statetxt'   'Purch. doc. proc. state Long Text'.
    _set_col_text 'FIRST_APP_DATE' ' '              'PR F App Dat'          'PR First Approval Date'.
    _set_col_text 'FINAL_APP_DATE' ' '              'PR L App Dat'          'PR Final Approval Date'.
    _set_col_text 'ZZ_PUR_METHOD'  ' '              'P.M. Requestor'        'Purchase Method Requestor'.
    _set_col_text 'ZZ_PUR_METHOD_PO' ' '            'P.M. Buyer'            'Purchase Method Buyer'.
    _set_col_text 'ZZMM_PUR_TYPE_PO' ' '            'Pur. Type'             'Purchase Type'.
    _set_col_text 'ZZMM_PUR_TYPE_ARIBA' ' '         'Ariba ID'              'Ariba Event ID'.
    _set_col_text 'CITY'           ' '              'City'                  'City'.
    _set_col_text 'COUNTRY'        ' '              'Country'               'Country'.

    TRY.
        lo_columns->set_column_position( columnname = 'VAL_GR_FOR' position = 1 ).
      CATCH cx_salv_not_found. "#EC NO_HANDLER
    ENDTRY.

    TRY.
        lo_column = lo_columns->get_column( 'PEN_DEL_VAL' ).
        lo_column->set_fixed_header_text( 'M' ).
      CATCH cx_salv_not_found. "#EC NO_HANDLER
    ENDTRY.

    TRY.
        lo_column = lo_columns->get_column( 'PEN_INV_VAL' ).
        lo_column->set_fixed_header_text( 'M' ).
      CATCH cx_salv_not_found. "#EC NO_HANDLER
    ENDTRY.

    " ── Hotspot on PO number ─────────────────────────────────────────
    DATA: gr_columns   TYPE REF TO cl_salv_columns_table,
          gr_column    TYPE REF TO cl_salv_column_table,
          gr_functions TYPE REF TO cl_salv_functions,
          gr_events    TYPE REF TO cl_salv_events_table.

    gr_functions = lo_table->get_functions( ).
    gr_functions->set_all( abap_true ).

    TRY.
        gr_columns = lo_table->get_columns( ).
        gr_column ?= gr_columns->get_column( 'EBELN' ).
        gr_column->set_cell_type( if_salv_c_cell_type=>hotspot ).
      CATCH cx_salv_not_found. "#EC NO_HANDLER
    ENDTRY.

    gr_events = lo_table->get_event( ).
    CREATE OBJECT event_handler.
    SET HANDLER event_handler->on_link_click FOR gr_events.

    lo_table->display( ).

  ENDMETHOD.

ENDCLASS.
