<?xml version="1.0" encoding="UTF-8"?>

<xsl:stylesheet xmlns:cp="vsap:cp" xmlns:xsl="http://www.w3.org/1999/XSL/Transform" version="1.0">
<xsl:import href="../cp_global.xsl" />

<xsl:variable name="message">
  <xsl:if test="string(/cp/msgs/msg)">
    <xsl:copy-of select="/cp/strings/*[local-name()=/cp/msgs/msg/@name]" />
  </xsl:if>
</xsl:variable>

<xsl:variable name="feedback">
  <xsl:if test="$message != ''">
    <xsl:call-template name="feedback_table">
      <xsl:with-param name="image">
        <xsl:choose>
          <xsl:when test="/cp/vsap/vsap[@type='error']">error</xsl:when>
          <xsl:otherwise>success</xsl:otherwise>
        </xsl:choose>
      </xsl:with-param>
      <xsl:with-param name="message">
        <xsl:copy-of select="$message" />
      </xsl:with-param>
    </xsl:call-template>
  </xsl:if>
</xsl:variable>

<xsl:variable name="app"><xsl:value-of select="/cp/form/application"/></xsl:variable>

<xsl:variable name="pan"><xsl:value-of select="/cp/strings/*[name()=concat('application_name_',$app)]"/></xsl:variable>
<xsl:variable name="display_name">
 <xsl:choose>
   <xsl:when test="string($pan)"><xsl:value-of select="$pan"/></xsl:when>
   <xsl:otherwise><xsl:value-of select="$app"/></xsl:otherwise>
 </xsl:choose>
</xsl:variable>

<xsl:variable name="config_bc_title">
  <xsl:call-template name="transliterate">
    <xsl:with-param name="string"><xsl:value-of select="/cp/strings/bc_system_admin_config_file"/></xsl:with-param>
    <xsl:with-param name="search">__APPLICATION__</xsl:with-param>
    <xsl:with-param name="replace" select="$display_name"/>
  </xsl:call-template>
</xsl:variable>

<xsl:variable name="config_nv_title">
  <xsl:call-template name="transliterate">
    <xsl:with-param name="string"><xsl:value-of select="/cp/strings/nv_admin_config_file"/></xsl:with-param>
    <xsl:with-param name="search">__APPLICATION__</xsl:with-param>
    <xsl:with-param name="replace" select="$display_name"/>
  </xsl:call-template>
</xsl:variable>

<xsl:variable name="config_file_edit_instr">
  <xsl:call-template name="transliterate">
    <xsl:with-param name="string"><xsl:value-of select="/cp/strings/config_file_edit_instr"/></xsl:with-param>
    <xsl:with-param name="search">__APPLICATION__</xsl:with-param>
    <xsl:with-param name="replace" select="$display_name"/>
  </xsl:call-template>
</xsl:variable>

<xsl:variable name="config_path">
  <xsl:choose>
    <xsl:when test="/cp/form/config_path">
      <xsl:value-of select="/cp/form/config_path"/>
    </xsl:when>
    <xsl:otherwise>
      <xsl:value-of select="/cp/vsap/vsap[@type='sys:configfile:fetch']/file/path"/>
    </xsl:otherwise>
  </xsl:choose>
</xsl:variable>

<xsl:variable name="num_backups_available">
  <xsl:choose>
    <xsl:when test="string(/cp/vsap/vsap[@type='sys:configfile:list_backups']/num_backups_available)">
      <xsl:value-of select="/cp/vsap/vsap[@type='sys:configfile:list_backups']/num_backups_available"/>
    </xsl:when>
    <xsl:otherwise>
      <xsl:value-of select="count(/cp/vsap/vsap[@type='sys:configfile:list_backups']/backup)"/>
    </xsl:otherwise>
  </xsl:choose>
</xsl:variable>

<xsl:variable name="num_columns">
  <xsl:value-of select="count(/cp/vsap/vsap[@type='sys:configfile:fetch']/file)"/>
</xsl:variable>

<xsl:variable name="contents">
  <xsl:choose>
    <xsl:when test="/cp/form/contents">
      <xsl:value-of select="/cp/form/contents"/>
    </xsl:when>
    <xsl:when test="string(/cp/form/config_path) and (count(/cp/vsap/vsap[@type='sys:configfile:fetch']/file) &gt; 1)">
      <xsl:value-of select="/cp/vsap/vsap[@type='sys:configfile:fetch']/file[path = /cp/form/config_path]/contents"/>
    </xsl:when>
    <xsl:otherwise>
      <xsl:value-of select="/cp/vsap/vsap[@type='sys:configfile:fetch']/file[1]/contents"/>
    </xsl:otherwise>
  </xsl:choose>
</xsl:variable>

<xsl:variable name="nav_item">
  <xsl:choose>
    <xsl:when test="($app = 'dovecot') or ($app = 'ftp') or ($app = 'httpd') or ($app = 'postfix')">
      <xsl:value-of select="/cp/strings/nv_admin_manage_services" />
    </xsl:when>
    <xsl:otherwise>
      <xsl:value-of select="/cp/strings/nv_admin_manage_applications" />
    </xsl:otherwise>
  </xsl:choose>
</xsl:variable>

<xsl:template match="/">
  <xsl:call-template name="bodywrapper">
    <xsl:with-param name="title"><xsl:copy-of select="/cp/strings/cp_title" /> : <xsl:copy-of select="$config_bc_title" /></xsl:with-param>
    <xsl:with-param name="formaction">config_file.xsl</xsl:with-param>
    <xsl:with-param name="feedback" select="$feedback" />
    <xsl:with-param name="selected_navandcontent" select="$nav_item" />
    <xsl:with-param name="help_short" select="/cp/strings/system_admin_hlp_short" />
    <xsl:with-param name="help_long"><xsl:copy-of select="/cp/strings/system_admin_hlp_long" /></xsl:with-param>
    <xsl:with-param name="breadcrumb">
      <breadcrumb>
        <section>
          <name><xsl:copy-of select="/cp/strings/bc_system_admin_applications" /></name>
          <url><xsl:value-of select="$base_url"/>/cp/admin/applications.xsl</url>
        </section>
        <section>
          <name><xsl:copy-of select="$config_bc_title" /></name>
          <url>#</url>
          <image>SystemAdministration</image>
        </section>
      </breadcrumb>
    </xsl:with-param>
  </xsl:call-template>
</xsl:template>

<xsl:template name="content">

        <script src="{concat($base_url, '/cp/admin/config_file.js')}" language="javascript"/>

        <input type="hidden" name="recover" value="" />
        <input type="hidden" name="save" value="" />
        <input type="hidden" name="cancel" value="" />
        <input type="hidden" name="application" value="{$app}" />
        <input type="hidden" name="config_path" value="{$config_path}" />

        <table class="formview" border="0" cellspacing="0" cellpadding="0">
          <tr class="title">
            <td colspan="{$num_columns}"><xsl:copy-of select="/cp/strings/config_file_edit_title" /></td>
          </tr>
          <tr class="instructionrow">
            <td colspan="{$num_columns}"><xsl:value-of select="$config_file_edit_instr"/></td>
          </tr>
          <tr class="columnhead">
            <td class="appstatcolumn" colspan="{$num_columns}">
              <xsl:value-of select="/cp/strings/config_file_path"/>&#160;
              <xsl:value-of select="$config_path"/>
              <xsl:if test="$num_backups_available > 0">
                <span class="floatright">
                  <a href="{$base_url}/cp/admin/config_file_restore.xsl?application={$app}&amp;config_path={$config_path}">
                  <xsl:value-of select="/cp/strings/config_file_backups_available"/>&#160;
                  <xsl:value-of select="$num_backups_available"/></a>&#160;
                </span>
              </xsl:if>
            </td>
          </tr>
          <tr class="rowodd">
            <td colspan="{$num_columns}">
              <textarea name="contents" rows="16" cols="96" wrap="off"><xsl:value-of select="$contents"/></textarea>
              <br/>
            </td>
          </tr>
          <xsl:if test="$num_columns &gt; 1">
            <tr class="roweven">
              <td class="label"><xsl:value-of select="/cp/strings/config_file_other"/></td>
              <td class="contentwidth">
                <xsl:for-each select="/cp/vsap/vsap[@type='sys:configfile:fetch']/file">
                  <xsl:if test="./path != $config_path">
                    <a href="{$base_url}/cp/admin/config_file.xsl?application={$app}&amp;config_path={./path}"
                       onClick="return discardConfigConfirm('{cp:js-escape(/cp/strings/config_file_js_discard_changes)}')">
                      <xsl:value-of select="./path"/>
                    </a>
                  </xsl:if>
                </xsl:for-each>
              </td>
            </tr>
          </xsl:if>
          <tr class="controlrow">
            <td colspan="{$num_columns}">
              <xsl:if test="$num_backups_available > 0">
                <input type="button" name="btn_recover" value="{/cp/strings/config_file_recover_btn}"
                  onClick="document.forms[0].recover.value='yes'; document.forms[0].submit();" />
              </xsl:if>
              <span class="floatright">
                <input type="submit" name="btn_save" value="{/cp/strings/btn_save}"
                  onClick="return showEditConfigAlert('{cp:js-escape(/cp/strings/config_file_js_no_changes)}',
                                                      '{cp:js-escape(/cp/strings/config_file_js_save_alert)}');"/>
                <input type="button" name="btn_cancel" value="{/cp/strings/btn_cancel}"
                  onClick="document.forms[0].cancel.value='yes'; document.forms[0].submit();" /></span></td>
          </tr>
        </table>

        <!-- the original -->
        <input type="hidden" name="original" value="{$contents}" />

</xsl:template>

</xsl:stylesheet>
