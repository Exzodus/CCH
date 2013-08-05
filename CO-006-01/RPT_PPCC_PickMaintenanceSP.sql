
/****** Object:  StoredProcedure [dbo].[RPT_PPCC_PickMaintenanceSP]    Script Date: 07/12/2013 10:36:46 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO

CREATE procedure [dbo].[RPT_PPCC_PickMaintenanceSP]
(
@StartCustomer				CustNumType
,@EndCustomer				CustNumType
,@StartCustOrder			CoNumType
,@EndCustOrder				CoNumType
,@StartPickListNo			PickListIDType
,@EndPickListNo				PickListIDType
,@StartCustPo				CustPoType
,@EndCustPo					CustPoType
,@StartDueDate				DateTime
,@EndDueDate				DateTime 
)
AS

BEGIN TRANSACTION
SET XACT_ABORT ON
SET ARITHABORT ON
IF dbo.GetIsolationLevel(N'RPT_PPCC_PickMaintenanceSP') = N'COMMITTED'
   SET TRANSACTION ISOLATION LEVEL READ COMMITTED 
ELSE 
   SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED
DECLARE
  @RptSessionID RowPointerType

EXEC dbo.InitSessionContextSp
  @ContextName = 'RPT_PPCC_PickMaintenanceSP'
, @SessionID   = @RptSessionID OUTPUT


SET @StartCustomer			= ISNULL(@StartCustomer,dbo.LowString('CustNumType'))
SET @EndCustomer			= ISNULL(@EndCustomer,dbo.HighString('CustNumType'))

SET @StartCustOrder			= ISNULL(@StartCustOrder,dbo.LowString('CoNumType'))
SET @EndCustOrder			= ISNULL(@EndCustOrder,dbo.HighString('CoNumType'))

SET @StartPickListNo		= ISNULL(@StartPickListNo,dbo.LowInt())
SET @EndPickListNo			= ISNULL(@EndPickListNo,dbo.HighInt())

SET @StartCustPo			= ISNULL(@StartCustPo,dbo.LowString('CustPoType'))
SET @EndCustPo				= ISNULL(@EndCustPo,dbo.HighString('CustPoType'))

SET @StartDueDate			= ISNULL(@StartDueDate,'1900/01/01') + ' 00:00:00'
SET @EndDueDate				= ISNULL(@EndDueDate,'3000/01/01') + ' 23:59:59'


select
p.pick_list_id as PickListNo
,p.whse
,pl.loc
,p.pick_date
,ci.due_date
,pf.sequence
--,(select SUM(qty) as QtyOnHand from matltran
--where whse = p.whse and loc = pl.loc and item = ci.item )as  QtyOnHand
,il.qty_on_hand as Qty_On_Hand
,pf.qty_to_pick
,ci.co_num
,ci.item 
,i.description as ItemDesc
,i.u_m
,c.cust_num
,ca.name as CustName
,isnull(c.cust_po,'') as CustPO
,(isnull(ca.addr##1,'') + ISNULL(ca.addr##2,'')) as ShipAddr
,n.Description as RemSubject
,n.Note as  Remark
from pick_list_ref as pf
inner join pick_list_loc as pl on pf.pick_list_id =pl.pick_list_id and pf.sequence = pl.sequence
inner join pick_list as p on pf.pick_list_id = p.pick_list_id
inner join coitem as ci on pf.ref_num = ci.co_num and pf.ref_line_suf = ci.co_line and pf.ref_release  = ci.co_release
inner join item as i on ci.item = i.item 
inner join itemloc as il on i.item = il.item and p.whse = il.whse and pl.loc = il.loc and il.mrb_flag = 0
left outer join co as c on ci.co_num = c.co_num
left outer join custaddr as ca on c.cust_num = ca.cust_num and c.cust_seq = ca.cust_seq 
left outer join ReportNotesView as n on p.RowPointer = n.RefRowPointer and n.TableName ='pick_list'
where p.status IN ('O','P')
and c.cust_num between @StartCustomer and @EndCustomer
and ci.co_num between @StartCustOrder and @EndCustOrder
and p.pick_list_id between @StartPickListNo and @EndPickListNo
and isnull(c.cust_po,'') between @StartCustPo and @EndCustPo
and ci.due_date between @StartDueDate and @EndDueDate




COMMIT TRANSACTION
EXEC dbo.CloseSessionContextSp @SessionID = @RptSessionID
RETURN 0
GO


