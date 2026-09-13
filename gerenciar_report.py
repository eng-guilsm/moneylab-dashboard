#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
gerenciar_report.py
==============================================================================
Utilitário de Gestão de Feedbacks, Sugestões e Bugs Reportados via /report.
Permite listar relatos, alterar status (em análise, resolvido, anulado)
e disparar notificações automáticas no Telegram diretamente para o solicitante.
==============================================================================
"""

import os
import sys
import re
import argparse
import urllib.request
import urllib.parse
import json

sys.stdout.reconfigure(encoding='utf-8')

LOG_FILE = "reports_usuarios.log"
CONFIG_AUTH = "config_auth.R"

def get_tg_token():
    paths = [CONFIG_AUTH, os.path.join("..", CONFIG_AUTH), "/home/ubuntu/moneylab-dashboard/config_auth.R", "/app/config_auth.R"]
    for p in paths:
        if os.path.exists(p):
            with open(p, "r", encoding="utf-8") as f:
                for line in f:
                    if "TG_INVEST_TOKEN" in line and "<-" in line:
                        token = line.split("<-")[1].strip().replace('"', '').replace("'", '').split("#")[0].strip()
                        if token:
                            return token
    return os.getenv("TG_INVEST_TOKEN", "")

def parse_reports(log_path):
    if not os.path.exists(log_path):
        return []
    
    with open(log_path, "r", encoding="utf-8") as f:
        content = f.read()
    
    blocks = content.split("================================================================================")
    reports = []
    
    for b in blocks:
        b_clean = b.strip()
        if not b_clean:
            continue
        
        rep = {}
        lines = b_clean.splitlines()
        msg_lines = []
        is_msg = False
        
        for line in lines:
            if is_msg:
                msg_lines.append(line)
                continue
            
            if line.startswith("ID:"):
                rep["id"] = line.replace("ID:", "").strip()
            elif line.startswith("DATA:"):
                rep["data"] = line.replace("DATA:", "").strip()
            elif line.startswith("USUARIO:"):
                rep["usuario_raw"] = line.replace("USUARIO:", "").strip()
                m_chat = re.search(r"CHAT_ID:\s*(-?\d+)", rep["usuario_raw"])
                rep["chat_id"] = m_chat.group(1) if m_chat else None
            elif line.startswith("STATUS:"):
                rep["status"] = line.replace("STATUS:", "").strip()
            elif line.startswith("PARECER:"):
                rep["parecer"] = line.replace("PARECER:", "").strip()
            elif line.startswith("NOTIFICADO:"):
                rep["notificado"] = line.replace("NOTIFICADO:", "").strip()
            elif line.startswith("MENSAGEM:"):
                is_msg = True
        
        rep["mensagem"] = "\n".join(msg_lines).strip()
        if "id" in rep:
            reports.append(rep)
            
    return reports

def save_reports(log_path, reports):
    with open(log_path, "w", encoding="utf-8") as f:
        for r in reports:
            f.write("================================================================================\n")
            f.write(f"ID: {r.get('id', '')}\n")
            f.write(f"DATA: {r.get('data', '')}\n")
            f.write(f"USUARIO: {r.get('usuario_raw', '')}\n")
            f.write(f"STATUS: {r.get('status', 'em análise')}\n")
            f.write(f"PARECER: {r.get('parecer', '')}\n")
            f.write(f"NOTIFICADO: {r.get('notificado', 'NAO')}\n")
            f.write("MENSAGEM:\n")
            f.write(f"{r.get('mensagem', '')}\n")
            f.write("================================================================================\n\n")

def send_telegram_notification(token, chat_id, report_id, status, parecer):
    if not token or not chat_id:
        print(f"⚠️ Erro: Token ({bool(token)}) ou Chat ID ({chat_id}) ausente. Notificação não enviada.")
        return False
    
    emoji = "✅" if status.lower() == "resolvido" else "ℹ️"
    msg_text = (
        f"{emoji} <b>ATUALIZAÇÃO DO SEU RELATO (#{report_id})</b>\n"
        f"━━━━━━━━━━━━━━━━━━━━━━━━━━━━\n\n"
        f"📌 <b>Status:</b> <code>{status.upper()}</code>\n\n"
        f"💬 <b>Parecer da Equipe:</b>\n"
        f"<i>\"{parecer}\"</i>\n\n"
        f"<i>Obrigado por nos ajudar a aperfeiçoar o ecossistema MoneyLab!</i>"
    )
    
    url = f"https://api.telegram.org/bot{token}/sendMessage"
    payload = {
        "chat_id": chat_id,
        "text": msg_text,
        "parse_mode": "HTML"
    }
    
    try:
        data = json.dumps(payload).encode("utf-8")
        req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=10) as resp:
            res_json = json.loads(resp.read().decode())
            return res_json.get("ok", False)
    except Exception as e:
        print(f"❌ Falha ao enviar notificação Telegram: {e}")
        return False

def main():
    parser = argparse.ArgumentParser(description="Gerenciador de Reports do MoneyLab Telegram Bot")
    parser.add_argument("--list", action="store_true", help="Listar todos os relatos")
    parser.add_argument("--pendentes", action="store_true", help="Listar apenas relatos pendentes ('em análise')")
    parser.add_argument("--atualizar", action="store_true", help="Atualizar status e parecer de um relato")
    parser.add_argument("--id", type=str, help="ID do relato (ex: REP-20260913-174501)")
    parser.add_argument("--status", type=str, choices=["resolvido", "em análise", "anulado"], help="Novo status")
    parser.add_argument("--parecer", type=str, help="Texto do parecer técnico / resposta ao usuário")
    parser.add_argument("--log", type=str, default=LOG_FILE, help="Caminho do arquivo reports_usuarios.log")
    
    args = parser.parse_args()
    reports = parse_reports(args.log)
    
    if args.list or (not args.pendentes and not args.atualizar):
        print(f"\n=== RELATOS DE USUÁRIOS NO SISTEMA ({len(reports)} encontrados) ===")
        if not reports:
            print("Nenhum relato registrado no log.")
        for r in reports:
            print("-" * 70)
            print(f"ID:        {r['id']} | DATA: {r['data']}")
            print(f"USUÁRIO:   {r['usuario_raw']}")
            print(f"STATUS:    [{r['status'].upper()}] | NOTIFICADO: {r.get('notificado', 'NAO')}")
            print(f"PARECER:   {r.get('parecer', 'N/D')}")
            print(f"MENSAGEM:  {r['mensagem']}")
        print("=" * 70 + "\n")
        return

    if args.pendentes:
        pendentes = [r for r in reports if r.get("status", "").lower() == "em análise"]
        print(f"\n=== RELATOS PENDENTES DE AVALIAÇÃO ({len(pendentes)}) ===")
        if not pendentes:
            print("Nenhum relato pendente no momento. Todos foram avaliados!")
        for r in pendentes:
            print("-" * 70)
            print(f"ID:        {r['id']} | DATA: {r['data']}")
            print(f"USUÁRIO:   {r['usuario_raw']}")
            print(f"MENSAGEM:  {r['mensagem']}")
        print("=" * 70 + "\n")
        return

    if args.atualizar:
        if not args.id or not args.status:
            print("❌ Erro: --atualizar requer --id e --status.")
            sys.exit(1)
        
        parecer_texto = args.parecer or ("Avaliado pelo administrador." if args.status == "resolvido" else "Relato anulado pelo administrador.")
        encontrado = False
        
        for r in reports:
            if r["id"] == args.id:
                encontrado = True
                r["status"] = args.status
                r["parecer"] = parecer_texto
                
                if args.status in ["resolvido", "anulado"]:
                    token = get_tg_token()
                    chat_id = r.get("chat_id")
                    print(f"Notificando usuário no Chat ID {chat_id}...")
                    sucesso = send_telegram_notification(token, chat_id, r["id"], args.status, parecer_texto)
                    if sucesso:
                        r["notificado"] = "SIM"
                        print(f"✅ Notificação enviada com sucesso no Telegram!")
                    else:
                        print("⚠️ Notificação não pôde ser entregue imediatamente.")
                break
        
        if not encontrado:
            print(f"❌ Relato com ID '{args.id}' não foi encontrado no arquivo {args.log}.")
            sys.exit(1)
            
        save_reports(args.log, reports)
        print(f"✅ Relato {args.id} atualizado com sucesso para '{args.status}'!")

if __name__ == "__main__":
    main()
