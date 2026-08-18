-- ============================================================================
-- VITAFOAM ERP INTEGRE - Supabase PostgreSQL
-- Version prototype fonctionnelle : Articles + Stock + Budget + Production
-- IMPORTANT : ce script REINITIALISE les tables du prototype dans public.
-- A exécuter dans Supabase > SQL Editor sur le projet vgmcwpoinnuzjkkzntmt.
-- ============================================================================

create extension if not exists pgcrypto;

-- Nettoyage du prototype précédent
DROP VIEW IF EXISTS public.v_of_summary CASCADE;
DROP TABLE IF EXISTS public.confection_consumptions CASCADE;
DROP TABLE IF EXISTS public.confection_batches CASCADE;
DROP TABLE IF EXISTS public.debitage_wastes CASCADE;
DROP TABLE IF EXISTS public.debitage_outputs CASCADE;
DROP TABLE IF EXISTS public.debitage_runs CASCADE;
DROP TABLE IF EXISTS public.block_weighings CASCADE;
DROP TABLE IF EXISTS public.viking_consumptions CASCADE;
DROP TABLE IF EXISTS public.viking_runs CASCADE;
DROP TABLE IF EXISTS public.production_order_standards CASCADE;
DROP TABLE IF EXISTS public.stock_movements CASCADE;
DROP TABLE IF EXISTS public.production_orders CASCADE;
DROP TABLE IF EXISTS public.bom_lines CASCADE;
DROP TABLE IF EXISTS public.bom_headers CASCADE;
DROP TABLE IF EXISTS public.articles CASCADE;
DROP SEQUENCE IF EXISTS public.of_number_seq CASCADE;

-- --------------------------------------------------------------------------
-- ARTICLES : référentiel unique ancien ERP + production
-- --------------------------------------------------------------------------
CREATE TABLE public.articles (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  code text NOT NULL UNIQUE,
  designation text,
  intitule text,
  categorie text NOT NULL DEFAULT 'DIVERS',
  societe text NOT NULL DEFAULT 'VT',
  nature text,
  longueur numeric(12,3),
  largeur numeric(12,3),
  hauteur numeric(12,3),
  tissus text,
  gaine_oui boolean NOT NULL DEFAULT false,
  gaine_code text,
  colle_type text,
  gestion_stock boolean NOT NULL DEFAULT true,
  sites text[] NOT NULL DEFAULT ARRAY[]::text[],
  surface_mousse numeric(18,6),
  volume_mousse numeric(18,6),
  quantite_tissus numeric(18,6),
  article_type text CHECK (article_type IN ('MP','BLOC','SEMI_FINI','PSF','PF','CHUTE')),
  unite text NOT NULL DEFAULT 'pièce',
  pru_reference numeric(18,4) NOT NULL DEFAULT 0 CHECK (pru_reference >= 0),
  active boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION public.normalize_article()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.intitule := COALESCE(NULLIF(NEW.intitule,''), NULLIF(NEW.designation,''), NEW.code);
  NEW.designation := COALESCE(NULLIF(NEW.designation,''), NULLIF(NEW.intitule,''), NEW.code);
  IF NEW.article_type IS NULL THEN
    NEW.article_type := CASE
      WHEN NEW.code LIKE 'B-%' OR COALESCE(NEW.nature,'') LIKE 'BLOC-%' THEN 'BLOC'
      WHEN NEW.categorie = 'MP' THEN 'MP'
      WHEN NEW.categorie = 'SF' THEN 'SEMI_FINI'
      WHEN NEW.categorie = 'PSF' THEN 'PSF'
      WHEN NEW.categorie = 'PF' THEN 'PF'
      ELSE 'PSF'
    END;
  END IF;
  IF NEW.unite IS NULL OR NEW.unite='' THEN
    NEW.unite := CASE WHEN NEW.article_type='MP' THEN 'kg' ELSE 'pièce' END;
  END IF;
  NEW.updated_at := now();
  RETURN NEW;
END $$;

CREATE TRIGGER trg_normalize_article
BEFORE INSERT OR UPDATE ON public.articles
FOR EACH ROW EXECUTE FUNCTION public.normalize_article();

-- --------------------------------------------------------------------------
-- NOMENCLATURES BLOC
-- --------------------------------------------------------------------------
CREATE TABLE public.bom_headers (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  parent_article_id uuid NOT NULL REFERENCES public.articles(id),
  version integer NOT NULL DEFAULT 1 CHECK(version > 0),
  valid_from date NOT NULL DEFAULT current_date,
  valid_to date,
  active boolean NOT NULL DEFAULT true,
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE(parent_article_id,version)
);

CREATE TABLE public.bom_lines (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  bom_id uuid NOT NULL REFERENCES public.bom_headers(id) ON DELETE CASCADE,
  component_id uuid NOT NULL REFERENCES public.articles(id),
  qty_standard numeric(14,4) NOT NULL CHECK(qty_standard >= 0),
  unite text NOT NULL,
  UNIQUE(bom_id,component_id)
);

CREATE SEQUENCE public.of_number_seq START 1;

-- --------------------------------------------------------------------------
-- OF
-- --------------------------------------------------------------------------
CREATE TABLE public.production_orders (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  of_number text NOT NULL UNIQUE,
  block_article_id uuid NOT NULL REFERENCES public.articles(id),
  planned_blocks integer NOT NULL CHECK(planned_blocks > 0),
  bom_id uuid NOT NULL REFERENCES public.bom_headers(id),
  site text NOT NULL DEFAULT 'VITA',
  planned_date date,
  status text NOT NULL DEFAULT 'PLANIFIE' CHECK(status IN(
    'PLANIFIE','VIKING_EN_COURS','A_DEBITER','DEBITAGE_EN_COURS',
    'A_CONFECTIONNER','CONFECTION_EN_COURS','TERMINE','CLOTURE'
  )),
  notes text,
  created_at timestamptz NOT NULL DEFAULT now(),
  updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.production_order_standards (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  of_id uuid NOT NULL REFERENCES public.production_orders(id) ON DELETE CASCADE,
  component_id uuid NOT NULL REFERENCES public.articles(id),
  qty_per_block numeric(14,4) NOT NULL,
  qty_planned numeric(14,4) NOT NULL,
  unite text NOT NULL,
  UNIQUE(of_id,component_id)
);

CREATE TABLE public.viking_runs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  of_id uuid NOT NULL UNIQUE REFERENCES public.production_orders(id) ON DELETE CASCADE,
  produced_blocks integer NOT NULL CHECK(produced_blocks>=0),
  conform_blocks integer NOT NULL CHECK(conform_blocks>=0),
  head_blocks integer NOT NULL DEFAULT 0 CHECK(head_blocks>=0),
  nonconforming_blocks integer NOT NULL DEFAULT 0 CHECK(nonconforming_blocks>=0),
  other_waste_kg numeric(14,3) NOT NULL DEFAULT 0 CHECK(other_waste_kg>=0),
  notes text,
  validated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.viking_consumptions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  of_id uuid NOT NULL REFERENCES public.production_orders(id) ON DELETE CASCADE,
  component_id uuid NOT NULL REFERENCES public.articles(id),
  actual_qty numeric(14,4) NOT NULL CHECK(actual_qty>=0),
  pru numeric(18,4) NOT NULL DEFAULT 0 CHECK(pru>=0),
  value numeric(20,4) GENERATED ALWAYS AS(actual_qty*pru) STORED,
  UNIQUE(of_id,component_id)
);

CREATE TABLE public.block_weighings (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  of_id uuid NOT NULL REFERENCES public.production_orders(id) ON DELETE CASCADE,
  block_no integer NOT NULL CHECK(block_no>0),
  weight_kg numeric(14,3) NOT NULL CHECK(weight_kg>0),
  UNIQUE(of_id,block_no)
);

CREATE TABLE public.debitage_runs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  of_id uuid NOT NULL UNIQUE REFERENCES public.production_orders(id) ON DELETE CASCADE,
  input_blocks integer NOT NULL,
  input_weight_kg numeric(14,3) NOT NULL,
  material_gap_kg numeric(14,3) NOT NULL DEFAULT 0,
  notes text,
  validated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.debitage_outputs (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  of_id uuid NOT NULL REFERENCES public.production_orders(id) ON DELETE CASCADE,
  article_id uuid NOT NULL REFERENCES public.articles(id),
  output_type text NOT NULL CHECK(output_type IN('CONFORME','SOUPLE')),
  qty_pcs integer NOT NULL CHECK(qty_pcs>=0),
  weight_kg numeric(14,3) NOT NULL CHECK(weight_kg>=0),
  transferred_to_confection boolean NOT NULL DEFAULT true,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.debitage_wastes (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  of_id uuid NOT NULL REFERENCES public.production_orders(id) ON DELETE CASCADE,
  waste_type text NOT NULL CHECK(waste_type IN('CROUTE','CHEMELLE','FILEMENT','AUTRE')),
  weight_kg numeric(14,3) NOT NULL CHECK(weight_kg>=0),
  UNIQUE(of_id,waste_type)
);

CREATE TABLE public.confection_batches (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  of_id uuid NOT NULL REFERENCES public.production_orders(id) ON DELETE CASCADE,
  source_output_id uuid NOT NULL REFERENCES public.debitage_outputs(id),
  finished_article_id uuid NOT NULL REFERENCES public.articles(id),
  finish_type text NOT NULL CHECK(finish_type IN('TISSU_GAINE','GAINE_SEULE')),
  qty_input integer NOT NULL CHECK(qty_input>0),
  qty_finished integer NOT NULL CHECK(qty_finished>=0),
  qty_reject integer NOT NULL DEFAULT 0 CHECK(qty_reject>=0),
  validated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE public.confection_consumptions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  batch_id uuid NOT NULL REFERENCES public.confection_batches(id) ON DELETE CASCADE,
  component_id uuid NOT NULL REFERENCES public.articles(id),
  actual_qty numeric(14,4) NOT NULL CHECK(actual_qty>=0),
  pru numeric(18,4) NOT NULL DEFAULT 0 CHECK(pru>=0),
  value numeric(20,4) GENERATED ALWAYS AS(actual_qty*pru) STORED
);

-- --------------------------------------------------------------------------
-- MOUVEMENTS DE STOCK : communs aux mouvements manuels et à la production
-- --------------------------------------------------------------------------
CREATE TABLE public.stock_movements (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  of_id uuid REFERENCES public.production_orders(id),
  article_id uuid NOT NULL REFERENCES public.articles(id),
  movement_type text NOT NULL CHECK(movement_type IN('ENTREE','SORTIE','TRANSFERT','CHUTE')),
  atelier_from text,
  atelier_to text,
  qty numeric(14,4) NOT NULL CHECK(qty>=0),
  unite text NOT NULL,
  pru numeric(18,4) NOT NULL DEFAULT 0 CHECK(pru>=0),
  site text,
  motif text,
  reference text,
  note text,
  movement_date date NOT NULL DEFAULT current_date,
  created_at timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX idx_of_status ON public.production_orders(status);
CREATE INDEX idx_stock_article ON public.stock_movements(article_id);
CREATE INDEX idx_stock_date ON public.stock_movements(movement_date);
CREATE INDEX idx_stock_of ON public.stock_movements(of_id);

-- --------------------------------------------------------------------------
-- RPC : création OF + gel nomenclature
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.create_production_order(
  p_block_article_id uuid,
  p_planned_blocks integer,
  p_notes text DEFAULT NULL,
  p_site text DEFAULT 'VITA',
  p_planned_date date DEFAULT NULL
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_bom uuid; v_id uuid; v_num text;
BEGIN
  IF p_planned_blocks<=0 THEN RAISE EXCEPTION 'La quantité prévue doit être supérieure à zéro'; END IF;
  SELECT id INTO v_bom FROM bom_headers
  WHERE parent_article_id=p_block_article_id AND active=true
    AND valid_from<=current_date AND (valid_to IS NULL OR valid_to>=current_date)
  ORDER BY version DESC LIMIT 1;
  IF v_bom IS NULL THEN RAISE EXCEPTION 'Aucune nomenclature active pour ce bloc'; END IF;
  v_num := 'OF-'||to_char(current_date,'YYYYMMDD')||'-'||lpad(nextval('of_number_seq')::text,4,'0');
  INSERT INTO production_orders(of_number,block_article_id,planned_blocks,bom_id,site,planned_date,notes)
  VALUES(v_num,p_block_article_id,p_planned_blocks,v_bom,COALESCE(p_site,'VITA'),p_planned_date,p_notes)
  RETURNING id INTO v_id;
  INSERT INTO production_order_standards(of_id,component_id,qty_per_block,qty_planned,unite)
  SELECT v_id,component_id,qty_standard,qty_standard*p_planned_blocks,unite FROM bom_lines WHERE bom_id=v_bom;
  RETURN v_id;
END $$;

-- --------------------------------------------------------------------------
-- RPC : Viking/Séchoir
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.validate_viking(
 p_of_id uuid,p_produced_blocks integer,p_conform_blocks integer,p_head_blocks integer,
 p_nonconforming_blocks integer,p_other_waste_kg numeric,p_notes text,
 p_consumptions jsonb,p_weighings jsonb
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE x jsonb; v_count integer; v_weight numeric; v_block uuid; v_site text;
BEGIN
 IF EXISTS(SELECT 1 FROM viking_runs WHERE of_id=p_of_id) THEN RAISE EXCEPTION 'Viking déjà validé pour cet OF'; END IF;
 IF p_produced_blocks<0 OR p_conform_blocks<0 OR p_conform_blocks>p_produced_blocks THEN RAISE EXCEPTION 'Nombre de blocs incohérent'; END IF;
 v_count:=jsonb_array_length(COALESCE(p_weighings,'[]'::jsonb));
 IF v_count<>p_conform_blocks THEN RAISE EXCEPTION 'Le nombre de pesées (%) doit être égal au nombre de blocs conformes (%)',v_count,p_conform_blocks; END IF;
 INSERT INTO viking_runs(of_id,produced_blocks,conform_blocks,head_blocks,nonconforming_blocks,other_waste_kg,notes)
 VALUES(p_of_id,p_produced_blocks,p_conform_blocks,COALESCE(p_head_blocks,0),COALESCE(p_nonconforming_blocks,0),COALESCE(p_other_waste_kg,0),p_notes);
 FOR x IN SELECT * FROM jsonb_array_elements(COALESCE(p_consumptions,'[]'::jsonb)) LOOP
   INSERT INTO viking_consumptions(of_id,component_id,actual_qty,pru)
   VALUES(p_of_id,(x->>'component_id')::uuid,COALESCE((x->>'actual_qty')::numeric,0),COALESCE((x->>'pru')::numeric,0));
   SELECT site INTO v_site FROM production_orders WHERE id=p_of_id;
   INSERT INTO stock_movements(of_id,article_id,movement_type,atelier_from,qty,unite,pru,site,motif,reference)
   SELECT p_of_id,(x->>'component_id')::uuid,'SORTIE','STOCK MP',COALESCE((x->>'actual_qty')::numeric,0),a.unite,COALESCE((x->>'pru')::numeric,0),v_site,'production','Consommation Viking'
   FROM articles a WHERE a.id=(x->>'component_id')::uuid;
 END LOOP;
 FOR x IN SELECT * FROM jsonb_array_elements(COALESCE(p_weighings,'[]'::jsonb)) LOOP
   INSERT INTO block_weighings(of_id,block_no,weight_kg) VALUES(p_of_id,(x->>'block_no')::int,(x->>'weight_kg')::numeric);
 END LOOP;
 SELECT COALESCE(sum(weight_kg),0) INTO v_weight FROM block_weighings WHERE of_id=p_of_id;
 SELECT block_article_id,site INTO v_block,v_site FROM production_orders WHERE id=p_of_id;
 INSERT INTO stock_movements(of_id,article_id,movement_type,atelier_from,atelier_to,qty,unite,site,motif,reference)
 VALUES(p_of_id,v_block,'TRANSFERT','VIKING/SECHOIR','DEBITAGE',v_weight,'kg',v_site,'production','Bloc pesé après séchage');
 UPDATE production_orders SET status='A_DEBITER',updated_at=now() WHERE id=p_of_id;
 RETURN jsonb_build_object('blocks',p_conform_blocks,'weight_kg',v_weight);
END $$;

-- --------------------------------------------------------------------------
-- RPC : Débitage/Tamponnage avec contrôle bilan matière
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.validate_debitage(
 p_of_id uuid,p_outputs jsonb,p_wastes jsonb,p_notes text DEFAULT NULL,p_tolerance_kg numeric DEFAULT 0.05
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE x jsonb; v_in numeric; v_out numeric:=0; v_waste numeric:=0; v_gap numeric; v_blocks int; v_site text;
BEGIN
 IF EXISTS(SELECT 1 FROM debitage_runs WHERE of_id=p_of_id) THEN RAISE EXCEPTION 'Débitage déjà validé pour cet OF'; END IF;
 SELECT COALESCE(sum(weight_kg),0),count(*) INTO v_in,v_blocks FROM block_weighings WHERE of_id=p_of_id;
 IF v_in<=0 THEN RAISE EXCEPTION 'Aucune pesée après séchage disponible'; END IF;
 FOR x IN SELECT * FROM jsonb_array_elements(COALESCE(p_outputs,'[]'::jsonb)) LOOP v_out:=v_out+COALESCE((x->>'weight_kg')::numeric,0); END LOOP;
 FOR x IN SELECT * FROM jsonb_array_elements(COALESCE(p_wastes,'[]'::jsonb)) LOOP v_waste:=v_waste+COALESCE((x->>'weight_kg')::numeric,0); END LOOP;
 v_gap:=round(v_in-v_out-v_waste,3);
 IF abs(v_gap)>p_tolerance_kg THEN RAISE EXCEPTION 'Bilan matière non équilibré : entrée % kg, sorties % kg, chutes % kg, écart % kg',v_in,v_out,v_waste,v_gap; END IF;
 INSERT INTO debitage_runs(of_id,input_blocks,input_weight_kg,material_gap_kg,notes) VALUES(p_of_id,v_blocks,v_in,v_gap,p_notes);
 SELECT site INTO v_site FROM production_orders WHERE id=p_of_id;
 FOR x IN SELECT * FROM jsonb_array_elements(COALESCE(p_outputs,'[]'::jsonb)) LOOP
   INSERT INTO debitage_outputs(of_id,article_id,output_type,qty_pcs,weight_kg)
   VALUES(p_of_id,(x->>'article_id')::uuid,x->>'output_type',(x->>'qty_pcs')::int,(x->>'weight_kg')::numeric);
   INSERT INTO stock_movements(of_id,article_id,movement_type,atelier_from,atelier_to,qty,unite,site,motif,reference)
   VALUES(p_of_id,(x->>'article_id')::uuid,'TRANSFERT','DEBITAGE','CONFECTION',(x->>'qty_pcs')::numeric,'pièce',v_site,'production',x->>'output_type');
 END LOOP;
 FOR x IN SELECT * FROM jsonb_array_elements(COALESCE(p_wastes,'[]'::jsonb)) LOOP
   INSERT INTO debitage_wastes(of_id,waste_type,weight_kg) VALUES(p_of_id,x->>'waste_type',COALESCE((x->>'weight_kg')::numeric,0));
 END LOOP;
 UPDATE production_orders SET status='A_CONFECTIONNER',updated_at=now() WHERE id=p_of_id;
 RETURN jsonb_build_object('input_kg',v_in,'outputs_kg',v_out,'wastes_kg',v_waste,'gap_kg',v_gap);
END $$;

-- --------------------------------------------------------------------------
-- RPC : Confection
-- --------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.validate_confection_batch(
 p_of_id uuid,p_source_output_id uuid,p_finished_article_id uuid,p_finish_type text,
 p_qty_input integer,p_qty_finished integer,p_qty_reject integer,p_consumptions jsonb
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_batch uuid; v_available int; v_used int; v_source_type text; v_site text; x jsonb;
BEGIN
 SELECT qty_pcs,output_type INTO v_available,v_source_type FROM debitage_outputs WHERE id=p_source_output_id AND of_id=p_of_id;
 IF v_available IS NULL THEN RAISE EXCEPTION 'Sortie débitage introuvable'; END IF;
 SELECT COALESCE(sum(qty_input),0) INTO v_used FROM confection_batches WHERE source_output_id=p_source_output_id;
 IF p_qty_input<=0 OR p_qty_input>(v_available-v_used) THEN RAISE EXCEPTION 'Quantité supérieure au disponible (%)',v_available-v_used; END IF;
 IF p_qty_finished+p_qty_reject<>p_qty_input THEN RAISE EXCEPTION 'PF + rebut doit être égal à la quantité entrée'; END IF;
 IF v_source_type='SOUPLE' AND p_finish_type<>'GAINE_SEULE' THEN RAISE EXCEPTION 'Le souple doit recevoir une gaine seule'; END IF;
 INSERT INTO confection_batches(of_id,source_output_id,finished_article_id,finish_type,qty_input,qty_finished,qty_reject)
 VALUES(p_of_id,p_source_output_id,p_finished_article_id,p_finish_type,p_qty_input,p_qty_finished,p_qty_reject) RETURNING id INTO v_batch;
 SELECT site INTO v_site FROM production_orders WHERE id=p_of_id;
 FOR x IN SELECT * FROM jsonb_array_elements(COALESCE(p_consumptions,'[]'::jsonb)) LOOP
   INSERT INTO confection_consumptions(batch_id,component_id,actual_qty,pru)
   VALUES(v_batch,(x->>'component_id')::uuid,COALESCE((x->>'actual_qty')::numeric,0),COALESCE((x->>'pru')::numeric,0));
   INSERT INTO stock_movements(of_id,article_id,movement_type,atelier_from,qty,unite,pru,site,motif,reference)
   SELECT p_of_id,(x->>'component_id')::uuid,'SORTIE','CONFECTION',COALESCE((x->>'actual_qty')::numeric,0),a.unite,COALESCE((x->>'pru')::numeric,0),v_site,'production','Consommation confection'
   FROM articles a WHERE a.id=(x->>'component_id')::uuid;
 END LOOP;
 INSERT INTO stock_movements(of_id,article_id,movement_type,atelier_from,atelier_to,qty,unite,site,motif,reference)
 VALUES(p_of_id,p_finished_article_id,'ENTREE','CONFECTION','STOCK PF',p_qty_finished,'pièce',v_site,'production','Produit fini');
 UPDATE production_orders SET status='CONFECTION_EN_COURS',updated_at=now() WHERE id=p_of_id;
 RETURN v_batch;
END $$;

CREATE OR REPLACE FUNCTION public.close_production_order(p_of_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path=public AS $$
DECLARE v_remaining int;
BEGIN
 SELECT COALESCE((SELECT sum(qty_pcs) FROM debitage_outputs WHERE of_id=p_of_id),0)-COALESCE((SELECT sum(qty_input) FROM confection_batches WHERE of_id=p_of_id),0) INTO v_remaining;
 IF v_remaining>0 THEN RAISE EXCEPTION 'Impossible de clôturer : % pièce(s) restent à confectionner',v_remaining; END IF;
 UPDATE production_orders SET status='TERMINE',updated_at=now() WHERE id=p_of_id;
END $$;

-- --------------------------------------------------------------------------
-- Vue de synthèse
-- --------------------------------------------------------------------------
CREATE VIEW public.v_of_summary AS
SELECT po.id,po.of_number,po.status,po.site,po.planned_date,po.planned_blocks,po.created_at,
       a.code block_code,a.designation block_designation,
       vr.produced_blocks,vr.conform_blocks,
       COALESCE((SELECT sum(weight_kg) FROM block_weighings b WHERE b.of_id=po.id),0) weight_after_drying_kg,
       COALESCE((SELECT sum(weight_kg) FROM debitage_outputs d WHERE d.of_id=po.id AND d.output_type='CONFORME'),0) conform_kg,
       COALESCE((SELECT sum(weight_kg) FROM debitage_outputs d WHERE d.of_id=po.id AND d.output_type='SOUPLE'),0) souple_kg,
       COALESCE((SELECT sum(weight_kg) FROM debitage_wastes w WHERE w.of_id=po.id),0) wastes_kg,
       COALESCE((SELECT sum(qty_finished) FROM confection_batches c WHERE c.of_id=po.id),0) finished_pcs
FROM production_orders po JOIN articles a ON a.id=po.block_article_id LEFT JOIN viking_runs vr ON vr.of_id=po.id;

-- --------------------------------------------------------------------------
-- RLS PROTOTYPE : pour fonctionnement immédiat avec la clé anon publique.
-- A sécuriser avec Supabase Auth + rôles avant mise en production réelle.
-- --------------------------------------------------------------------------
DO $$ DECLARE t text; BEGIN
 FOREACH t IN ARRAY ARRAY['articles','bom_headers','bom_lines','production_orders','production_order_standards','viking_runs','viking_consumptions','block_weighings','debitage_runs','debitage_outputs','debitage_wastes','confection_batches','confection_consumptions','stock_movements'] LOOP
   EXECUTE format('ALTER TABLE public.%I ENABLE ROW LEVEL SECURITY',t);
   EXECUTE format('CREATE POLICY prototype_all ON public.%I FOR ALL TO anon USING (true) WITH CHECK (true)',t);
 END LOOP;
END $$;

GRANT USAGE ON SCHEMA public TO anon,authenticated;
GRANT SELECT,INSERT,UPDATE,DELETE ON ALL TABLES IN SCHEMA public TO anon,authenticated;
GRANT USAGE,SELECT ON ALL SEQUENCES IN SCHEMA public TO anon,authenticated;
GRANT EXECUTE ON FUNCTION public.create_production_order(uuid,integer,text,text,date) TO anon,authenticated;
GRANT EXECUTE ON FUNCTION public.validate_viking(uuid,integer,integer,integer,integer,numeric,text,jsonb,jsonb) TO anon,authenticated;
GRANT EXECUTE ON FUNCTION public.validate_debitage(uuid,jsonb,jsonb,text,numeric) TO anon,authenticated;
GRANT EXECUTE ON FUNCTION public.validate_confection_batch(uuid,uuid,uuid,text,integer,integer,integer,jsonb) TO anon,authenticated;
GRANT EXECUTE ON FUNCTION public.close_production_order(uuid) TO anon,authenticated;
GRANT SELECT ON public.v_of_summary TO anon,authenticated;

-- --------------------------------------------------------------------------
-- Données techniques de départ
-- --------------------------------------------------------------------------
INSERT INTO articles(code,designation,intitule,categorie,societe,nature,article_type,unite,gestion_stock,sites,pru_reference) VALUES
('B-SGA','BLOC SGA','BLOC SGA','PSF','VT','BLOC-SGA','BLOC','bloc',true,ARRAY['VITA'],469615),
('B-SGB','BLOC SGB','BLOC SGB','PSF','VT','BLOC-SGB','BLOC','bloc',true,ARRAY['VITA'],497256),
('B-SGC','BLOC SGC','BLOC SGC','PSF','VT','BLOC-SGC','BLOC','bloc',true,ARRAY['VITA'],664259),
('B-SGD','BLOC SGD','BLOC SGD','PSF','VT','BLOC-SGD','BLOC','bloc',true,ARRAY['VITA'],682908),
('B-SGN','BLOC SGN','BLOC SGN','PSF','VT','BLOC-SGN','BLOC','bloc',true,ARRAY['VITA'],0),
('MP-POLYOL','Polyol','Polyol','MP','VT','CHIMIQUE','MP','kg',true,ARRAY['VITA'],0),
('MP-TDI','TDI','TDI','MP','VT','CHIMIQUE','MP','kg',true,ARRAY['VITA'],0),
('MP-SILICONE','Silicone','Silicone','MP','VT','CHIMIQUE','MP','kg',true,ARRAY['VITA'],0),
('MP-CATALYSEUR','Catalyseur','Catalyseur','MP','VT','CHIMIQUE','MP','kg',true,ARRAY['VITA'],0),
('PSF-TISSU','Tissu','Tissu','PSF','VT','TISSU','PSF','m²',true,ARRAY['VITA'],0),
('PSF-GAINE','Gaine','Gaine','PSF','VT','GAINE','PSF','pièce',true,ARRAY['VITA'],0),
('SF-SGA-196-148-20','SGA 196x148x20 débité','SGA 196x148x20 débité','SF','VT','SGA','SEMI_FINI','pièce',true,ARRAY['VITA'],0),
('SF-SGA-SOUPLE','SGA souple non tamponné','SGA souple non tamponné','SF','VT','SGA','SEMI_FINI','pièce',true,ARRAY['VITA'],0),
('PF-SGA-196-148-20','Matelas SGA 196x148x20','Matelas SGA 196x148x20','PF','VT','SGA','PF','pièce',true,ARRAY['VITA'],0),
('PF-SGA-SOUPLE','Matelas SGA souple gainé','Matelas SGA souple gainé','PF','VT','SGA','PF','pièce',true,ARRAY['VITA'],0)
ON CONFLICT(code) DO NOTHING;

-- Nomenclature SGA EXEMPLE uniquement : à remplacer dans l'écran Nomenclatures
DO $$ DECLARE p uuid; b uuid; BEGIN
 SELECT id INTO p FROM articles WHERE code='B-SGA';
 INSERT INTO bom_headers(parent_article_id,version,active,notes) VALUES(p,1,true,'EXEMPLE - remplacer par le standard réel VITAFOAM') RETURNING id INTO b;
 INSERT INTO bom_lines(bom_id,component_id,qty_standard,unite)
 SELECT b,a.id,x.q,x.u FROM (VALUES
 ('MP-POLYOL',30.0000::numeric,'kg'),('MP-TDI',15.0000::numeric,'kg'),('MP-SILICONE',0.5000::numeric,'kg'),('MP-CATALYSEUR',0.2000::numeric,'kg')
 ) x(code,q,u) JOIN articles a ON a.code=x.code;
END $$;
