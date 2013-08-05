
/****** Object:  StoredProcedure [dbo].[Rpt_PPCC_AccountsReceivableAgingSp]    Script Date: 07/26/2013 13:23:00 ******/
SET ANSI_NULLS ON
GO

SET QUOTED_IDENTIFIER ON
GO


CREATE PROCEDURE [dbo].[Rpt_PPCC_AccountsReceivableAgingSp](
   @CustomerStarting		CustNumType    = NULL
   ,@CustomerEnding			CustNumType    = NULL
   ,@SaleTeamIDStarting		SalesTeamIDType = NULL
   ,@SaleTeamIDEnding		SalesTeamIDType = NULL 

   ,@AgingDate				DATETIME       = NULL

   ,@SiteGroup				SiteGroupType = NULL
   ,@ReportType				CHAR(1)     = NULL
   ,@SortBy					CHAR(1)     = NULL

)
AS

BEGIN TRANSACTION
SET XACT_ABORT ON

IF dbo.GetIsolationLevel(N'PPCC_AccountsReceivableAgingReport') = N'COMMITTED'
   SET TRANSACTION ISOLATION LEVEL READ COMMITTED
ELSE
   SET TRANSACTION ISOLATION LEVEL READ UNCOMMITTED

-- A session context is created so session variables can be used.
DECLARE
  @RptSessionID RowPointerType
, @Today DateType

EXEC dbo.InitSessionContextSp
  @ContextName = 'Rpt_PPCC_AccountsReceivableAgingSp'
, @SessionID   = @RptSessionID OUTPUT


DECLARE @Site_GroupStart			SiteGroupType
DECLARE @Site_GroupEnd				SiteGroupType
--SET @Site_Group = 'DEMO'
--SET @CustomerStarting     = ISNULL(@CustomerStarting,dbo.LowString('CustNumType'))
--SET @CustomerStarting =1
SET @CustomerStarting		= ISNULL( dbo.ExpandKyByType('CustNumType', @CustomerStarting), dbo.LowCharacter())
SET @CustomerEnding			= ISNULL( dbo.ExpandKyByType('CustNumType', @CustomerEnding), dbo.HighCharacter())
SET @SaleTeamIDStarting     = ISNULL( dbo.ExpandKyByType('SalesTeamIDType', @SaleTeamIDStarting), dbo.LowCharacter())
SET @SaleTeamIDEnding       = ISNULL( dbo.ExpandKyByType('SalesTeamIDType', @SaleTeamIDEnding), dbo.HighCharacter())

IF ISNULL(@SiteGroup ,'') = ''
	BEGIN
		SET @Site_GroupStart			=ISNULL(dbo.ExpandKyByType('SiteGroupType',@SiteGroup),dbo.LowCharacter())
		SET @Site_GroupEnd				=ISNULL(dbo.ExpandKyByType('SiteGroupType',@SiteGroup),dbo.HighCharacter())
	END
ELSE 
	BEGIN
		SET @Site_GroupStart			=@SiteGroup
		SET @Site_GroupEnd				=@SiteGroup
	END
SET @AgingDate	= ISNULL(@AgingDate,GETDATE())
SET @AgingDate = @AgingDate + ' 23:59:59.000'

DECLARE @Report TABLE (
		Site_Group		SiteGroupType
		,Site_Ref		SiteType
		,EndUserType	EndUserTypeType
		,Customer	CustNumType
		,CustSeq	CustSeqType
		,CustName	NameType
		,AccType	ChartTypeType
		,AccCode	AcctType
		,AccName	DescriptionType
		,InvNum		InvNumType
		,InvDate	DateType
		,RvNum		ReferenceType
		,PaidDate	DateType
		,InvAmount	AmountType
		,PaymentAmount	AmountType
		,DepositAmount	AmountType
		,Balance	AmountType
		,SalesTeamID			SalesTeamIDType
		,SalesTeamName			NameType
		,SalesDesc				DescriptionType
	)
	
BEGIN
INSERT INTO @Report(
					Site_Group
					,Site_Ref
					,EndUserType		
					,Customer
					,CustSeq	
					,CustName	
					,AccCode	
					,InvNum		
					,InvDate			
					,InvAmount	
					,PaymentAmount
					,DepositAmount	
					,Balance
					,SalesTeamID
					,SalesTeamName
					,SalesDesc	
				)
			SELECT 
					site_group.site_group
					,ar.site_ref
					,t.end_user_type  
					,ar.cust_num
					,c.cust_seq
					,c.name
					,ar.acct
					,ar.inv_num
					,ar.inv_date
					,(isnull(ar.amount,0) + isnull(ar.misc_charges,0) + isnull(ar.freight,0)+isnull(ar.sales_tax,0))* isnull(ar.exch_rate,0)
					,0
					,0
					,(isnull(ar.amount,0) + isnull(ar.misc_charges,0) + isnull(ar.freight,0)+isnull(ar.sales_tax,0))* isnull(ar.exch_rate,0)
					,ISNULL(t.sales_team_id,'') AS SalesTeamID
					,ISNULL(st.Name,'') AS SalesTeamName
					,ISNULL(st.Description,'') AS SalesDesc
					FROM artran_all ar 					
					LEFT OUTER JOIN customer_all t ON ar.site_ref = t.site_ref and  ar.cust_num = t.cust_num and t.cust_seq = 0
					LEFT OUTER JOIN custaddr c ON t.cust_num = c.cust_num and c.cust_seq = 0
					INNER JOIN site_group ON site_group.site = ar.site_ref
					LEFT OUTER JOIN sales_team_all st ON t.site_ref = st.site_ref and  t.sales_team_id = st.sales_team_id
					WHERE type = 'I' 
					AND site_group.site_group between @Site_GroupStart and @Site_GroupEnd
					AND ar.cust_num		between	@CustomerStarting and @CustomerEnding
					AND ISNULL(t.sales_team_id,'')	between @SaleTeamIDStarting and @SaleTeamIDEnding				
					AND ar.inv_date		<= @AgingDate
		END
		
		BEGIN /*Update Invoice Amount Type 'D' */
			UPDATE @Report SET 
				InvAmount = isnull(rp.InvAmount,0) + ISNULL(t.SumPaymentAmount,0)								
				,Balance = (ISNULL(rp.InvAmount,0) + ISNULL(t.SumPaymentAmount,0)) - isnull(rp.PaymentAmount,0)
				
				FROM @Report as rp
				INNER JOIN
					( SELECT
					r.Site_Group
					,r.Site_Ref
					,r.Customer
					,r.CustSeq
					,r.InvNum 
					
					,sum(isnull(ar.amount,0))+ sum(isnull(ar.misc_charges,0))+ SUM(isnull(ar.freight,0))+ (sum(isnull(ar.sales_tax,0)) * sum(isnull(ar.exch_rate,0))) AS SumPaymentAmount
					FROM @Report as r
					Inner join site_group AS s on r.Site_Group = s.site_group and r.Site_Ref = s.site
					inner join artran_all AS ar on r.Customer = ar.cust_num and r.InvNum = ar.apply_to_inv_num and s.site = ar.site_ref
					GROUP BY r.Site_Group,r.Site_Ref,r.InvNum,ar.type,s.site_group,r.Customer,r.CustSeq
					HAVING ar.type='D' ) AS t ON rp.Site_Group = t.Site_Group and rp.Site_Ref = t.Site_Ref and rp.Customer = t.Customer and rp.CustSeq = t.CustSeq and rp.InvNum = t.InvNum 
			
							
		END

		BEGIN /*Update Payment Amount Type 'P'*/
				

			UPDATE @Report SET 
				PaymentAmount = ISNULL(t.SumPaymentAmount,0)	
				,Balance = ISNULL(rp.InvAmount,0) - ISNULL(t.SumPaymentAmount,0)
				--,RvNum = t.ref	
				FROM @Report as rp
				INNER JOIN
					( SELECT
					r.Site_Group
					,r.Site_Ref
					,r.Customer
					,r.CustSeq
					,r.InvNum 
					--,ar.ref
					,sum(isnull(ar.amount,0))+ sum(isnull(ar.misc_charges,0))+ SUM(isnull(ar.freight,0))+ (sum(isnull(ar.sales_tax,0)) * sum(isnull(ar.exch_rate,0))) as SumPaymentAmount
					FROM @Report AS r
					Inner join site_group AS s ON r.Site_Group = s.site_group and r.Site_Ref = s.site
					inner join artran_all AS ar ON r.Customer = ar.cust_num and r.InvNum = ar.inv_num and s.site = ar.site_ref
					GROUP BY r.Site_Group,r.Site_Ref,r.InvNum,ar.type,s.site_group,r.Customer,r.CustSeq
					HAVING ar.type='P' ) AS t ON rp.Site_Group = t.Site_Group and rp.Site_Ref = t.Site_Ref and rp.Customer = t.Customer and rp.CustSeq = t.CustSeq and rp.InvNum = t.InvNum 
			
					
		END /**/

		BEGIN /*Update Payment Amount Type 'C'*/
				
				UPDATE @Report SET 
						PaymentAmount = isnull(rp.PaymentAmount,0) + ISNULL(t.SumPaymentAmount,0)																
						,Balance = ISNULL(rp.InvAmount,0) - (ISNULL(t.SumPaymentAmount,0) + isnull(rp.PaymentAmount,0))
								
						FROM @Report as rp
						INNER JOIN
									( SELECT
									r.Site_Group
									,r.Site_Ref
									,r.Customer
									,r.CustSeq
									,r.InvNum 
									
									,sum(isnull(ar.amount,0))+ sum(isnull(ar.misc_charges,0))+ SUM(isnull(ar.freight,0))+ (sum(isnull(ar.sales_tax,0)) * sum(isnull(ar.exch_rate,0))) as SumPaymentAmount
									FROM @Report AS r
									Inner join site_group AS s ON r.Site_Group = s.site_group and r.Site_Ref = s.site
									inner join artran_all AS ar ON r.Customer = ar.cust_num and r.InvNum = ar.apply_to_inv_num and s.site = ar.site_ref
									GROUP BY r.Site_Group,r.Site_Ref,r.InvNum,ar.type,s.site_group,r.Customer,r.CustSeq
									HAVING ar.type='C' ) AS t ON rp.Site_Group = t.Site_Group and rp.Site_Ref = t.Site_Ref and rp.Customer = t.Customer and rp.CustSeq = t.CustSeq and rp.InvNum = t.InvNum 
							
						
					
		END /**/



		BEGIN /*Update Account Type and Description*/

			UPDATE @Report SET 
				AccName = description
				,AccType = type
			FROM @Report r left join chart c on c.acct = r.AccCode

		END 
			
		SELECT * FROM @Report



COMMIT TRANSACTION
EXEC dbo.CloseSessionContextSp @SessionID = @RptSessionID
GO


